-- =====================================================================
--  نادي القراءة الإماراتي – رحلة قارئ… حكاية وطن
--  مدرسة النهضة الوطنية للبنين
--  قاعدة البيانات ووظائف الخادم على Supabase (بديل Code.gs و Google Sheets)
--
--  طريقة التشغيل: Supabase ← SQL Editor ← الصق الملف كاملًا ← Run.
--  يمكن تشغيله أكثر من مرة دون أن يمس البيانات الموجودة.
-- =====================================================================

-- ---------- الجداول ----------
create table if not exists settings (key text primary key, value text not null default '');
create table if not exists sections (track text not null, grade text not null, section text primary key, sort int not null default 0);
create table if not exists allowed_students (email text primary key);
create table if not exists allowed_teachers (email text primary key);
create table if not exists supervisors (email text primary key);
create table if not exists test_emails (email text primary key);

create table if not exists students (
  email text primary key, name text not null, track text, grade text, section text,
  interest text default '', idea text default '', created_at timestamptz not null default now());

create table if not exists teachers (
  email text primary key, name text not null, sections text[] not null default '{}',
  status text not null default 'بانتظار الموافقة', created_at timestamptz not null default now());

create table if not exists submissions (
  id text primary key default substr(md5(random()::text || clock_timestamp()::text), 1, 8),
  created_at timestamptz not null default now(),
  email text not null, name text, track text, grade text, section text, station text,
  title text, descr text default '',
  file_path text,            -- ملف في مخزن Supabase
  file_url text,             -- رابط قديم (Google Drive) من البيانات المنقولة
  status text not null default 'قيد المراجعة', note text default '',
  approved_at timestamptz, reviewer text default '', reviewer_email text);
create index if not exists submissions_email on submissions(email);
create index if not exists submissions_section on submissions(section);

create table if not exists sessions (
  id text primary key default substr(md5(random()::text || clock_timestamp()::text), 1, 8),
  session_date date not null, section text not null, book text not null, count int not null,
  notes text default '', by_name text, by_email text, created_at timestamptz not null default now());

create table if not exists gallery (
  id text primary key default substr(md5(random()::text || clock_timestamp()::text), 1, 8),
  created_at timestamptz not null default now(), type text not null default 'صورة',
  title text not null, descr text default '', file_path text, url text, uploaded_by text);

create table if not exists certs (
  no text primary key, created_at timestamptz not null default now(), kind text not null, level int not null,
  email text not null, name text not null, level_name text, sub text, sig1 text, sig1_title text,
  url text);                 -- رابط PDF قديم من Drive (للشهادات المنقولة)
create index if not exists certs_email on certs(email);

create table if not exists outbox (
  id bigserial primary key, created_at timestamptz not null default now(),
  to_emails text not null, subject text not null, html text not null,
  sent_at timestamptz, error text);

create table if not exists previews (admin_email text primary key, test_email text not null, expires_at timestamptz not null);

-- لا وصول مباشر للجداول من المتصفح: كل شيء يمر عبر الوظائف أدناه
do $$ declare t text; begin
  foreach t in array array['settings','sections','allowed_students','allowed_teachers','supervisors','test_emails',
    'students','teachers','submissions','sessions','gallery','certs','outbox','previews'] loop
    execute format('alter table %I enable row level security', t);
  end loop; end $$;

-- ---------- القيم الافتراضية ----------
insert into settings(key, value) values
  ('owner_email', 'ضع_بريد_الأدمن_هنا@nahdaschools.com'),
  ('site_url', ''),
  ('school_principal', 'أ. أحلام أبو راضي'),
  ('club_supervisor', 'د. عبدالحفيظ طه جمعه'),
  ('coord_4_6', 'أ. شيماء سمير'),
  ('coord_7_12', 'أ. إبراهيم خليل')
on conflict (key) do nothing;

insert into test_emails values ('s0000001@nahdaschools.com') on conflict do nothing;

insert into sections(track, grade, section, sort)
select * from (
  select 'أمريكي', g::text, g::text || l, row_number() over ()::int
  from (values (4,'AB'),(5,'ABC'),(6,'ABC'),(7,'ABCD'),(8,'ABCD'),(9,'ABCDEFQ'),(10,'ABCDEFQ'),(11,'ABCDEFQR'),(12,'ABCDEFQR')) v(g, ls),
       regexp_split_to_table(ls, '') l
  union all
  select 'بريطاني', p, p || '-' || l, 1000 + row_number() over ()::int
  from (values ('Y5.GR4','GHIJK'),('Y6.GR5','GHIJKL'),('Y7.GR6','GHIJKL'),('Y8.GR7','GHIJKL'),('Y9.GR8','GHIJKL'),
               ('Y10.GR9','GH'),('Y11.GR10','GHI'),('Y12.GR11','G'),('Y13.GR12','GH')) v(p, ls),
       regexp_split_to_table(ls, '') l
) x
where not exists (select 1 from sections);

-- =====================================================================
--  أدوات داخلية (rc_)
-- =====================================================================
create or replace function rc_set(k text) returns text language sql stable security definer set search_path = public as
$$ select coalesce((select value from settings where key = k), '') $$;

create or replace function rc_put(k text, v text) returns void language sql security definer set search_path = public as
$$ insert into settings(key, value) values (k, v) on conflict (key) do update set value = excluded.value $$;

create or replace function rc_real() returns text language sql stable as
$$ select lower(coalesce(auth.jwt() ->> 'email', '')) $$;

create or replace function rc_clean(v text, mx int default 500) returns text language sql immutable as
$$ select left(btrim(coalesce(v, '')), mx) $$;

create or replace function rc_esc(v text) returns text language sql immutable as
$$ select replace(replace(replace(replace(coalesce(v, ''), '&', '&amp;'), '<', '&lt;'), '>', '&gt;'), '"', '&quot;') $$;

create or replace function rc_is_student_email(e text) returns boolean language sql immutable as
$$ select coalesce(e, '') ~ '^s\d+@nahdaschools\.com$' $$;

create or replace function rc_is_school_email(e text) returns boolean language sql immutable as
$$ select coalesce(e, '') ~ '^[^@\s]+@nahdaschools\.com$' $$;

create or replace function rc_is_owner(e text) returns boolean language sql stable security definer set search_path = public as
$$ select coalesce(e, '') <> '' and e = lower(rc_set('owner_email')) $$;

create or replace function rc_is_admin(e text) returns boolean language sql stable security definer set search_path = public as
$$ select rc_is_owner(e) or exists (select 1 from supervisors where email = e) $$;

create or replace function rc_is_test(e text) returns boolean language sql stable security definer set search_path = public as
$$ select exists (select 1 from test_emails where email = e) $$;

create or replace function rc_allowed(e text, teacher boolean) returns boolean language sql stable security definer set search_path = public as $$
  select rc_is_test(e) or case when teacher
    then not exists (select 1 from allowed_teachers) or exists (select 1 from allowed_teachers where email = e)
    else not exists (select 1 from allowed_students) or exists (select 1 from allowed_students where email = e) end
$$;

create or replace function rc_list(v text) returns text[] language sql immutable as $$
  select coalesce(array_agg(distinct x), '{}') from (
    select lower(btrim(x)) x from regexp_split_to_table(coalesce(v, ''), '[,،\s]+') x) t where x <> ''
$$;

create or replace function rc_admins() returns text language sql stable security definer set search_path = public as $$
  select string_agg(e, ',') from (select lower(rc_set('owner_email')) e union select email from supervisors) t where e like '%@%'
$$;

/* هوية المستخدم الحالي (أو الطالب التجريبي إن كان المشرف في وضع المعاينة) */
create or replace function rc_me() returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  r text := rc_real(); e text := rc_real(); pv boolean := false; t text;
  res jsonb; s students; tc teachers;
begin
  if rc_is_admin(r) then
    select test_email into t from previews where admin_email = r and expires_at > now();
    if t is not null and rc_is_test(t) then e := t; pv := true; end if;
  end if;
  res := jsonb_build_object('email', e, 'real', r, 'admin', false, 'preview', pv, 'kind', 'none',
                            'student', null, 'teacher', null, 'sections', '[]'::jsonb);
  if e = '' then return res; end if;
  res := res || jsonb_build_object('admin', (not pv) and rc_is_admin(e));
  if rc_is_student_email(e) then
    res := res || '{"kind":"student"}';
    select * into s from students where email = e;
    if found then
      res := res || jsonb_build_object('student', jsonb_build_object('name', s.name, 'track', s.track, 'grade', s.grade, 'section', s.section));
    end if;
  elsif rc_is_school_email(e) then
    res := res || '{"kind":"staff"}';
    select * into tc from teachers where email = e;
    if found then
      res := res || jsonb_build_object('teacher', jsonb_build_object('name', tc.name, 'status', tc.status, 'sections', array_to_string(tc.sections, ',')));
      if tc.status = 'مفعّل' then res := res || jsonb_build_object('sections', to_jsonb(tc.sections)); end if;
    end if;
  end if;
  return res;
end $$;

/* صلاحية المراجعة: المشرف يرى كل الشعب، والمعلم المفعّل يرى شعبه */
create or replace function rc_reviewer() returns jsonb language plpgsql stable security definer set search_path = public as $$
declare m jsonb := rc_me();
begin
  if (m ->> 'admin')::boolean then
    return jsonb_build_object('role', 'admin', 'name', 'المشرف', 'sections', null, 'email', m ->> 'email');
  end if;
  if m -> 'teacher' ->> 'status' = 'مفعّل' and rc_allowed(m ->> 'email', true) then
    return jsonb_build_object('role', 'teacher', 'name', m -> 'teacher' ->> 'name', 'sections', m -> 'sections', 'email', m ->> 'email');
  end if;
  raise exception 'ليست لديك صلاحية المراجعة';
end $$;

create or replace function rc_can(w jsonb, sec text) returns boolean language sql immutable as
$$ select jsonb_typeof(w -> 'sections') is distinct from 'array' or (w -> 'sections') ? coalesce(sec, '') $$;

create or replace function rc_need_admin() returns void language plpgsql stable security definer set search_path = public as $$
begin if not (rc_me() ->> 'admin')::boolean then raise exception 'هذه العملية للمشرف فقط'; end if; end $$;

create or replace function rc_need_owner() returns void language plpgsql stable security definer set search_path = public as $$
begin if not rc_is_owner(rc_real()) then raise exception 'هذه العملية للأدمن وحده'; end if; end $$;

create or replace function rc_is_summary(title text) returns boolean language sql immutable as
$$ select coalesce(title, '') like 'ملخص كتاب%' $$;

-- ---------- البريد (يُوضع في صندوق الصادر وتُرسله وظيفة send-mail) ----------
create or replace function rc_notify(to_list text, subject text, body text, btn text default null) returns void
language plpgsql security definer set search_path = public as $$
declare lst text; site text := nullif(rc_set('site_url'), '');
begin
  select string_agg(e, ',') into lst from (
    select distinct lower(btrim(e)) e from regexp_split_to_table(coalesce(to_list, ''), ',') e) t
  where rc_is_school_email(e) and not rc_is_test(e);
  if lst is null then return; end if;
  insert into outbox(to_emails, subject, html) values (lst, subject,
    '<div dir="rtl" style="font-family:Tahoma,Arial;font-size:15px;line-height:1.8;color:#183b2b;max-width:560px">'
    || '<div style="background:#16834d;color:#fff;padding:12px 16px;border-radius:10px 10px 0 0"><b>نادي القراءة الإماراتي</b> · رحلة قارئ… حكاية وطن</div>'
    || '<div style="border:1px solid #d6e6da;border-top:0;padding:16px;border-radius:0 0 10px 10px">' || body
    || case when site is null then '' else '<p style="margin-top:18px"><a href="' || site || '" style="background:#16834d;color:#fff;padding:9px 18px;border-radius:20px;text-decoration:none">' || coalesce(btn, 'افتح المنصة') || '</a></p>' end
    || '<p style="color:#7a8c80;font-size:12px">رسالة تلقائية من منصة نادي القراءة – مدرسة النهضة الوطنية للبنين.</p></div></div>');
end $$;

create or replace function rc_count_ar(n int, one text, two text, few text, many text) returns text language sql immutable as
$$ select case when n = 1 then one when n = 2 then two when n <= 10 then n || ' ' || few else n || ' ' || many end $$;
create or replace function rc_teacher_title(name text) returns text language sql immutable as
$$ select 'الأستاذ الفاضل ' || rc_esc(regexp_replace(coalesce(name, ''), '^أ\.\s*', '')) $$;
create or replace function rc_first(name text) returns text language sql immutable as
$$ select coalesce(split_part(btrim(coalesce(name, '')), ' ', 1), '') $$;
create or replace function rc_with_a(n text) returns text language sql immutable as
$$ select case when btrim(n) ~ '^(أ\.|د\.)' then btrim(n) else 'أ. ' || btrim(n) end $$;
create or replace function rc_grade_num(g text) returns int language sql immutable as
$$ select coalesce(substring(g from 'GR(\d+)'), substring(g from '^(\d+)'), '0')::int $$;
create or replace function rc_grade_label(track text, grade text) returns text language sql immutable as $$
  select 'الصف ' || coalesce((array['','','','الرابع','الخامس','السادس','السابع','الثامن','التاسع','العاشر','الحادي عشر','الثاني عشر'])[rc_grade_num(grade)], grade)
$$;

-- ---------- النقاط والمستويات ----------
create or replace function rc_levels(k text) returns jsonb language sql immutable as $$
  select case when k = 'student' then '[
    {"key":"bronze","name":"القارئ البرونزي","medal":"🥉","min":30},
    {"key":"silver","name":"القارئ الفضي","medal":"🥈","min":70},
    {"key":"gold","name":"القارئ الذهبي","medal":"🥇","min":120,"stamps":4},
    {"key":"amb","name":"سفير القراءة","medal":"💎","min":200,"stamps":4}]'::jsonb
  else '[
    {"key":"bronze","name":"المعلم المشارك","medal":"🥉","min":30},
    {"key":"silver","name":"المعلم الملهِم","medal":"🥈","min":80},
    {"key":"gold","name":"المعلم الرائد","medal":"🥇","min":150}]'::jsonb end
$$;

create or replace function rc_level_of(k text, pts int, stamps int) returns jsonb language plpgsql immutable as $$
declare L jsonb := rc_levels(k); i int := -1; j int; nx jsonb;
begin
  for j in 0 .. jsonb_array_length(L) - 1 loop
    if pts >= (L -> j ->> 'min')::int and (L -> j ->> 'stamps' is null or stamps >= (L -> j ->> 'stamps')::int) then i := j; end if;
  end loop;
  nx := L -> (i + 1);
  return jsonb_build_object('level', i,
    'levelName', case when i > -1 then L -> i ->> 'name' else 'مستكشف' end,
    'medal', case when i > -1 then L -> i ->> 'medal' else '🧭' end,
    'next', case when nx is null then null else jsonb_build_object('name', nx ->> 'name', 'medal', nx ->> 'medal',
      'need', greatest(0, (nx ->> 'min')::int - pts), 'stamps', coalesce((nx ->> 'stamps')::int, 0), 'min', (nx ->> 'min')::int) end);
end $$;

create or replace function rc_student_score(e text) returns jsonb language plpgsql stable security definer set search_path = public as $$
declare pts int; n int; cnt int;
begin
  select coalesce(sum(case when rc_is_summary(title) then 15 else 10 end), 0), count(distinct station), count(*)
    into pts, n, cnt from submissions where email = lower(e) and status = 'معتمد';
  pts := pts + 5 * n + case when n >= 4 then 20 else 0 end;
  return rc_level_of('student', pts, n) || jsonb_build_object('points', pts, 'stamps', n, 'approved', cnt, 'kind', 'student');
end $$;

create or replace function rc_teacher_score(e text) returns jsonb language plpgsql stable security definer set search_path = public as $$
declare t teachers; rv int; sm int; ss int; pts int;
begin
  select * into t from teachers where email = lower(e);
  if not found then return null; end if;
  select count(*) into rv from submissions
    where (reviewer_email = t.email or (reviewer_email is null and reviewer = t.name)) and status in ('معتمد', 'يحتاج تعديلًا');
  select count(*) into sm from submissions where section = any(t.sections) and status = 'معتمد' and rc_is_summary(title);
  select count(*) into ss from sessions where by_email = t.email;
  pts := rv * 2 + ss * 5 + sm;
  return rc_level_of('teacher', pts, 0) || jsonb_build_object('points', pts, 'reviews', rv, 'sessions', ss, 'summaries', sm, 'kind', 'teacher');
end $$;

create or replace function rc_next_line(o jsonb) returns text language plpgsql immutable as $$
declare p text[] := '{}'; nx jsonb := o -> 'next';
begin
  if nx is null or jsonb_typeof(nx) = 'null' then return 'بلغتَ أعلى المستويات، فأنت قدوة لزملائك في حب القراءة عن الوطن 🌟'; end if;
  if (nx ->> 'need')::int > 0 then p := p || ('بقيت <b>' || (nx ->> 'need') || ' نقطة</b>'); end if;
  if (nx ->> 'stamps')::int > 0 and (o ->> 'stamps')::int < (nx ->> 'stamps')::int then
    p := p || ('ينقصك ' || ((nx ->> 'stamps')::int - (o ->> 'stamps')::int) || ' من الأختام'); end if;
  if array_length(p, 1) is null then return ''; end if;
  return array_to_string(p, '، و') || ' لتبلغ مستوى ' || (nx ->> 'medal') || ' «' || (nx ->> 'name') || '».';
end $$;

create or replace function rc_issued_level(e text) returns int language sql stable security definer set search_path = public as
$$ select coalesce(max(level), -1) from certs where email = lower(e) $$;

create or replace function rc_issue_cert(k text, lvl int, e text, nm text, sb text, s1 text, s1t text) returns text
language plpgsql security definer set search_path = public as $$
declare no text; yr text := to_char(now() at time zone 'Asia/Dubai', 'YYYY');
begin
  perform pg_advisory_xact_lock(4242);
  no := 'NRC-' || yr || '-' || lpad(((select count(*) from certs) + 1)::text, 4, '0');
  insert into certs(no, kind, level, email, name, level_name, sub, sig1, sig1_title)
    values (no, k, lvl, lower(e), nm, rc_levels(k) -> lvl ->> 'name', sb, s1, s1t);
  return no;
end $$;

create or replace function rc_class_teacher(sec text, e text) returns text language sql stable security definer set search_path = public as $$
  select coalesce((select rc_with_a(t.name) from teachers t
    where t.status = 'مفعّل' and sec = any(t.sections)
    order by (select count(*) from submissions s where s.email = e and s.status = 'معتمد' and (s.reviewer_email = t.email or s.reviewer = t.name)) desc, t.created_at
    limit 1), '')
$$;

create or replace function rc_coordinator(secs text[]) returns text language sql stable security definer set search_path = public as $$
  select case when (select count(*) filter (where rc_grade_num(x) between 1 and 6) * 2 >= count(*) filter (where rc_grade_num(x) > 0)
                    from unnest(secs) x)
    then coalesce(nullif(rc_set('coord_4_6'), ''), 'أ. شيماء سمير')
    else coalesce(nullif(rc_set('coord_7_12'), ''), 'أ. إبراهيم خليل') end
$$;

create or replace function rc_check_student(e text, o jsonb, sub submissions) returns void language plpgsql security definer set search_path = public as $$
declare lvl int := (o ->> 'level')::int; L jsonb;
begin
  if lvl < 0 or rc_is_test(e) or rc_issued_level(e) >= lvl then return; end if;
  L := rc_levels('student') -> lvl;
  perform rc_issue_cert('student', lvl, e, sub.name, rc_grade_label(sub.track, sub.grade) || ' · الشعبة ' || sub.section,
                        rc_class_teacher(sub.section, e), 'معلم الصف');
  perform rc_notify(e, '🎉 مبارك يا ' || rc_first(sub.name) || '! بلغتَ مستوى «' || (L ->> 'name') || '»',
    '<p>يا ' || rc_esc(rc_first(sub.name)) || '، بقراءاتك وإنجازاتك بلغتَ مستوى ' || (L ->> 'medal') || ' <b>' || (L ->> 'name')
    || '</b> في رحلة «قارئ… حكاية وطن» برصيد <b>' || (o ->> 'points') || ' نقطة</b>.</p>'
    || '<p>صدرت لك شهادة تقدير باسمك، تجدها في جوازك على المنصة؛ احفظها وشاركها أهلك، فهم فخورون بك.</p>'
    || '<p>' || rc_next_line(o) || '</p>', 'افتح جوازك');
end $$;

create or replace function rc_check_teacher(e text) returns void language plpgsql security definer set search_path = public as $$
declare t teachers; o jsonb; lvl int; L jsonb;
begin
  select * into t from teachers where email = lower(e);
  if not found or t.status <> 'مفعّل' then return; end if;
  o := rc_teacher_score(e); lvl := (o ->> 'level')::int;
  if lvl < 0 or rc_issued_level(e) >= lvl then return; end if;
  L := rc_levels('teacher') -> lvl;
  perform rc_issue_cert('teacher', lvl, e, t.name, 'معلم اللغة العربية', rc_coordinator(t.sections), 'منسق مادة اللغة العربية');
  perform rc_notify(e, '🏅 شكرًا لك! بلغتَ مستوى «' || (L ->> 'name') || '»',
    '<p>' || rc_teacher_title(t.name) || '،</p><p>بفضل متابعتك لطلابك ومراجعتك لإنجازاتهم وجلسات النقاش التي تعقدها، بلغتَ مستوى '
    || (L ->> 'medal') || ' <b>' || (L ->> 'name') || '</b> في نادي القراءة الإماراتي.</p>'
    || '<p>صدرت لك شهادة تقدير باسمك تجدها في بوابة المعلم، عرفانًا بأثرك في صناعة جيل يقرأ وطنه.</p><p>'
    || case when o -> 'next' is null or jsonb_typeof(o -> 'next') = 'null' then 'بلغتَ أعلى مستويات المعلمين. شكرًا لك!'
       else 'المستوى التالي: ' || (o -> 'next' ->> 'medal') || ' ' || (o -> 'next' ->> 'name') || '.' end || '</p>', 'افتح بوابة المعلم');
end $$;

create or replace function rc_my_certs(e text) returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object('no', no, 'level', level_name, 'url', url,
    'date', to_char(created_at at time zone 'Asia/Dubai', 'YYYY/MM/DD')) order by created_at), '[]')
  from certs where email = lower(e)
$$;

-- =====================================================================
--  الوظائف التي تستدعيها الواجهة (نفس أسماء Code.gs بأحرف صغيرة)
--  كل وظيفة تأخذ وسائط عامة a, b, c من نوع jsonb
-- =====================================================================

create or replace function getsections() returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object('track', track, 'grade', grade, 'section', section) order by sort, section), '[]') from sections
$$;

create or replace function whoami() returns jsonb language plpgsql stable security definer set search_path = public as $$
declare m jsonb := rc_me(); e text := m ->> 'email';
begin
  return jsonb_build_object('email', e, 'kind', m ->> 'kind', 'admin', (m ->> 'admin')::boolean,
    'owner', not (m ->> 'preview')::boolean and rc_is_owner(e), 'preview', (m ->> 'preview')::boolean,
    'student', m -> 'student', 'teacher', m -> 'teacher',
    'testEmails', case when (m ->> 'admin')::boolean then (select coalesce(jsonb_agg(email order by email), '[]') from test_emails) else '[]' end,
    'allowed', case when e = '' or m ->> 'kind' = 'none' then false else rc_allowed(e, m ->> 'kind' <> 'student') end);
end $$;

create or replace function startpreview(a jsonb) returns boolean language plpgsql security definer set search_path = public as $$
declare r text := rc_real(); t text := lower(rc_clean(a #>> '{}', 120));
begin
  if not rc_is_admin(r) then raise exception 'هذه العملية للمشرف فقط'; end if;
  if not rc_is_test(t) then raise exception 'هذا البريد ليس ضمن «البريد التجريبي» في الإعدادات'; end if;
  insert into previews values (r, t, now() + interval '6 hours')
    on conflict (admin_email) do update set test_email = excluded.test_email, expires_at = excluded.expires_at;
  return true;
end $$;

create or replace function stoppreview() returns boolean language sql security definer set search_path = public as
$$ delete from previews where admin_email = rc_real(); select true $$;

/* ---------- الطلاب ---------- */
create or replace function joinclub(a jsonb) returns boolean language plpgsql security definer set search_path = public as $$
declare m jsonb := rc_me(); e text := m ->> 'email'; nm text := rc_clean(a ->> 'name', 80);
begin
  if m ->> 'kind' <> 'student' then raise exception 'الانضمام للطلاب فقط، ادخل بحسابك المدرسي الطلابي'; end if;
  if not rc_allowed(e, false) then raise exception 'حسابك غير مسجّل في قائمة طلاب المدرسة، راجع مشرف النادي'; end if;
  if jsonb_typeof(m -> 'student') = 'object' then raise exception 'أنت منضم من قبل'; end if;
  if nm = '' then raise exception 'اكتب اسمك الثلاثي'; end if;
  if not exists (select 1 from sections where track = a ->> 'track' and grade = a ->> 'grade' and section = a ->> 'section') then
    raise exception 'اختر المسار والصف والشعبة'; end if;
  insert into students(email, name, track, grade, section, interest, idea)
    values (e, nm || case when (m ->> 'preview')::boolean then ' (تجريبي)' else '' end,
            a ->> 'track', a ->> 'grade', a ->> 'section', rc_clean(a ->> 'interest', 60), rc_clean(a ->> 'idea', 800));
  return true;
end $$;

create or replace function submitachievement(a jsonb) returns text language plpgsql security definer set search_path = public as $$
declare m jsonb := rc_me(); e text := m ->> 'email'; s students; ttl text := rc_clean(a ->> 'title', 150);
  ds text := rc_clean(a ->> 'desc', 4000); bk text; au text; fp text := nullif(rc_clean(a ->> 'filePath', 400), ''); nid text;
  st text := rc_clean(a ->> 'station', 20);
begin
  select * into s from students where email = e;
  if not found then raise exception 'انضم إلى النادي أولًا'; end if;
  if not rc_allowed(e, false) then raise exception 'حسابك غير مسجّل في قائمة طلاب المدرسة'; end if;
  if st not in ('جذوري', 'قيمي', 'صوتي', 'أثري') then raise exception 'اختر المحطة'; end if;
  if fp is not null and split_part(fp, '/', 1) <> rc_real() then raise exception 'ملف غير صالح'; end if;
  if a ->> 'kind' = 'summary' then
    bk := rc_clean(a ->> 'book', 120); au := rc_clean(a ->> 'author', 80);
    if bk = '' then raise exception 'اكتب اسم الكتاب'; end if;
    if coalesce(array_length(regexp_split_to_array(btrim(ds), '\s+'), 1), 0) < 80 or btrim(ds) = '' then
      raise exception 'الملخص قصير؛ اكتب 80 كلمة على الأقل'; end if;
    ttl := 'ملخص كتاب: «' || bk || '»' || case when au <> '' then ' – ' || au else '' end;
  end if;
  if ttl = '' then raise exception 'اكتب عنوان الإنجاز'; end if;
  insert into submissions(email, name, track, grade, section, station, title, descr, file_path)
    values (e, s.name, s.track, s.grade, s.section, st, ttl, ds, fp) returning id into nid;
  return nid;
end $$;

create or replace function getstudent() returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', id, 'station', station, 'title', title, 'status', status, 'note', note) order by created_at), '[]')
  from submissions where email = rc_me() ->> 'email' and email <> ''
$$;

create or replace function getmyscore() returns jsonb language plpgsql stable security definer set search_path = public as $$
declare m jsonb := rc_me(); e text := m ->> 'email';
begin
  if jsonb_typeof(m -> 'student') = 'object' then return rc_student_score(e) || jsonb_build_object('certs', rc_my_certs(e)); end if;
  if m -> 'teacher' ->> 'status' = 'مفعّل' then return rc_teacher_score(e) || jsonb_build_object('certs', rc_my_certs(e)); end if;
  return null;
end $$;

/* ---------- المعلمون ---------- */
create or replace function registerteacher(a jsonb) returns boolean language plpgsql security definer set search_path = public as $$
declare m jsonb := rc_me(); e text := m ->> 'email'; nm text := rc_clean(a ->> 'name', 80); secs text[];
begin
  if m ->> 'kind' <> 'staff' then raise exception 'التسجيل هنا للمعلمين فقط'; end if;
  if not rc_allowed(e, true) then raise exception 'بريدك غير مسجّل ضمن معلمي المدرسة، راجع مشرف النادي'; end if;
  if jsonb_typeof(m -> 'teacher') = 'object' then raise exception 'لديك طلب أو حساب مسجّل من قبل'; end if;
  select coalesce(array_agg(distinct x), '{}') into secs
    from (select btrim(x) x from regexp_split_to_table(coalesce(a ->> 'sections', ''), ',') x) t
    where exists (select 1 from sections where section = x);
  if nm = '' then raise exception 'اكتب اسمك'; end if;
  if cardinality(secs) = 0 then raise exception 'اختر شعبة واحدة على الأقل'; end if;
  insert into teachers(email, name, sections) values (e, nm, secs);
  perform rc_notify(rc_admins(), '👤 طلب تسجيل معلم جديد: ' || nm,
    '<p>سجّل المعلم <b>' || rc_esc(nm) || '</b> (' || rc_esc(e) || ') في المنصة، وينتظر تفعيل حسابه.</p><p>الشعب: '
    || rc_esc(array_to_string(secs, '، ')) || '</p>', 'افتح بوابة المشرف');
  return true;
end $$;

create or replace function listteachers() returns jsonb language plpgsql stable security definer set search_path = public as $$
declare own boolean := rc_is_owner(rc_real());
begin
  perform rc_need_admin();
  return (select coalesce(jsonb_agg(jsonb_build_object('name', name, 'email', email, 'sections', array_to_string(sections, ','),
    'status', status, 'sup', exists (select 1 from supervisors s where s.email = t.email), 'canSet', own) order by created_at), '[]') from teachers t);
end $$;

create or replace function setsupervisor(a jsonb, b jsonb) returns boolean language plpgsql security definer set search_path = public as $$
declare e text := lower(rc_clean(a #>> '{}', 120)); onn boolean := coalesce((b #>> '{}')::boolean, false);
begin
  perform rc_need_owner();
  if not rc_is_school_email(e) or rc_is_student_email(e) then raise exception 'بريد غير صالح للإشراف'; end if;
  if not exists (select 1 from teachers where email = e) then raise exception 'لم يُعثر على المعلم'; end if;
  delete from supervisors where email = e;
  if onn then
    insert into supervisors values (e);
    perform rc_notify(e, '⭐ ثقة نعتز بها: عُيّنت مشرفًا في نادي القراءة',
      '<p>يسعدنا أن تنضم إلى فريق الإشراف على منصة «رحلة قارئ… حكاية وطن».</p><p>أصبح بإمكانك متابعة جميع الشعب، وتفعيل المعلمين، واعتماد الإنجازات، وإدارة معرض النادي. شكرًا لإسهامك في صناعة جيل يقرأ وطنه.</p>', 'افتح بوابة المشرف');
  end if;
  return true;
end $$;

create or replace function setteacherstatus(a jsonb, b jsonb) returns boolean language plpgsql security definer set search_path = public as $$
declare e text := lower(rc_clean(a #>> '{}', 120)); st text := b #>> '{}'; t teachers;
begin
  perform rc_need_admin();
  if st is null or st not in ('مفعّل', 'مرفوض', 'بانتظار الموافقة') then raise exception 'حالة غير معروفة'; end if;
  select * into t from teachers where email = e;
  if not found then raise exception 'لم يُعثر على المعلم'; end if;
  update teachers set status = st where email = e;
  if st = 'مفعّل' and t.status <> 'مفعّل' then
    perform rc_notify(e, '🎉 أهلًا بك في نادي القراءة الإماراتي', '<p>' || rc_teacher_title(t.name)
      || '،</p><p>فُعّل حسابك في منصة «رحلة قارئ… حكاية وطن»، وطلابك على موعد معك في رحلة القراءة عن الوطن.</p><p>ابدأ بمراجعة إنجازاتهم وختم جوازاتهم، وسجّل جلسات النقاش التي تعقدها معهم. كل مراجعة وكل جلسة تضيف إلى رصيدك نقاطًا توصلك إلى مستويات المعلمين وشهاداتها: 🥉 المعلم المشارك، 🥈 المعلم الملهِم، 🥇 المعلم الرائد.</p>', 'افتح بوابة المعلم');
  end if;
  return true;
end $$;

/* ---------- المراجعة ---------- */
create or replace function listsubmissions() returns jsonb language plpgsql stable security definer set search_path = public as $$
declare w jsonb := rc_reviewer();
begin
  return (select coalesce(jsonb_agg(jsonb_build_object('id', id, 'date', to_char(created_at at time zone 'Asia/Dubai', 'YYYY/MM/DD HH24:MI'),
    'name', name, 'track', track, 'grade', grade, 'section', section, 'station', station, 'title', title, 'desc', descr,
    'file', file_url, 'filePath', file_path, 'status', status, 'note', note, 'reviewer', reviewer) order by created_at desc), '[]')
    from submissions where rc_can(w, section));
end $$;

create or replace function reviewsubmission(a jsonb, b jsonb, c jsonb) returns boolean language plpgsql security definer set search_path = public as $$
declare w jsonb := rc_reviewer(); sid text := a #>> '{}'; act text := b #>> '{}'; nt text; s submissions; o jsonb; gain int;
begin
  select * into s from submissions where id = sid for update;
  if not found then raise exception 'لم يُعثر على المشاركة'; end if;
  if not rc_can(w, s.section) then raise exception 'هذه المشاركة ليست من شعبك'; end if;
  nt := case when c is null or jsonb_typeof(c) = 'null' then s.note else rc_clean(c #>> '{}', 800) end;
  update submissions set reviewer = w ->> 'name', reviewer_email = w ->> 'email', note = nt,
    status = case act when 'nominate' then 'مرشح للاعتماد' when 'approve' then 'معتمد' when 'reject' then 'يحتاج تعديلًا' else status end,
    approved_at = case when act = 'approve' then now() else approved_at end
  where id = sid returning * into s;

  if act = 'approve' then
    o := rc_student_score(s.email); gain := case when rc_is_summary(s.title) then 15 else 10 end;
    perform rc_notify(s.email, '🏅 أحسنت يا ' || rc_first(s.name) || '! ختمتَ محطة «' || s.station || '»',
      '<p>يا ' || rc_esc(rc_first(s.name)) || '، اعتمد معلمك إنجازك «' || rc_esc(s.title) || '»، وأُضيف ختم محطة <b>' || rc_esc(s.station)
      || '</b> إلى جواز سفرك القرائي، وكسبت <b>' || gain || ' نقطة</b>.</p><p>رصيدك الآن <b>' || (o ->> 'points') || ' نقطة</b>، ومستواك '
      || (o ->> 'medal') || ' <b>' || (o ->> 'levelName') || '</b>. ' || rc_next_line(o) || '</p>'
      || case when nt <> '' then '<p><b>كلمة معلمك:</b> ' || rc_esc(nt) || '</p>' else '' end
      || '<p>كل كتاب تقرؤه عن وطنك خطوة جديدة في رحلتك. واصل يا بطل! 🇦🇪</p>', 'افتح جوازك');
    perform rc_check_student(s.email, o, s);
  elsif act = 'reject' then
    perform rc_notify(s.email, '✏️ خطوة صغيرة ويكتمل إنجازك يا ' || rc_first(s.name),
      '<p>يا ' || rc_esc(rc_first(s.name)) || '، شكرًا لجهدك في إنجاز «' || rc_esc(s.title) || '». قرأه معلمك، ويطلب منك بعض التعديلات ليصبح جاهزًا للختم.</p>'
      || case when nt <> '' then '<p><b>ملاحظة معلمك:</b> ' || rc_esc(nt) || '</p>' else '' end
      || '<p>عدّل إنجازك وارفعه من جديد، فختم محطة «' || rc_esc(s.station) || '» بانتظارك!</p>', 'افتح جوازك');
  end if;
  if act in ('approve', 'reject') and w ->> 'role' = 'teacher' then perform rc_check_teacher(w ->> 'email'); end if;
  return true;
end $$;

create or replace function getstats() returns jsonb language plpgsql stable security definer set search_path = public as $$
declare w jsonb := rc_reviewer();
begin
  return jsonb_build_object(
    'pending', (select count(*) from submissions where rc_can(w, section) and status in ('قيد المراجعة', 'مرشح للاعتماد')),
    'approved', (select count(*) from submissions where rc_can(w, section) and status = 'معتمد'),
    'students', (select count(*) from students where rc_can(w, section)),
    'summaries', (select count(*) from submissions where rc_can(w, section) and status = 'معتمد' and rc_is_summary(title)),
    'sessions', (select count(*) from sessions where rc_can(w, section)),
    'teachersPending', case when w ->> 'role' = 'admin' then (select count(*) from teachers where status = 'بانتظار الموافقة') else 0 end);
end $$;

/* ---------- المعرض (الرفع للمشرفين فقط؛ الملف يُرفع إلى مخزن gallery من المتصفح) ---------- */
create or replace function addmedia(a jsonb) returns boolean language plpgsql security definer set search_path = public as $$
declare fp text := nullif(rc_clean(a ->> 'filePath', 400), ''); lk text := nullif(rc_clean(a ->> 'link', 600), ''); tt text := rc_clean(a ->> 'title', 120);
begin
  perform rc_need_admin();
  if tt = '' then raise exception 'اكتب عنوانًا'; end if;
  if fp is null and lk is null then raise exception 'اختر ملفًا أو الصق رابطًا'; end if;
  if lk is not null and lk !~ '^https://' then raise exception 'الرابط غير صحيح'; end if;
  insert into gallery(type, title, descr, file_path, url, uploaded_by) values (
    case when coalesce(a ->> 'fileType', '') like 'video%' or a ->> 'kind' = 'video' then 'فيديو' else 'صورة' end,
    tt, rc_clean(a ->> 'desc', 400), fp, lk, rc_real());
  return true;
end $$;

create or replace function listgallery() returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', id, 'date', to_char(created_at at time zone 'Asia/Dubai', 'YYYY/MM/DD'), 'type', type,
    'title', title, 'desc', descr, 'filePath', file_path, 'url', url) order by created_at desc), '[]')
  from gallery where rc_is_school_email(rc_real())
$$;

create or replace function deletemedia(a jsonb) returns text language plpgsql security definer set search_path = public as $$
declare fp text;
begin
  perform rc_need_admin();
  delete from gallery where id = a #>> '{}' returning coalesce(file_path, '') into fp;
  if fp is null then raise exception 'لم يُعثر على العنصر'; end if;
  return fp;   -- تحذف الواجهة الملف من المخزن
end $$;

/* ---------- إعدادات المنصة (للأدمن وحده) ---------- */
create or replace function getadminsettings() returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  perform rc_need_owner();
  return jsonb_build_object('owner', rc_set('owner_email'),
    'supervisors', (select coalesce(jsonb_agg(email order by email), '[]') from supervisors),
    'tests', (select coalesce(jsonb_agg(email order by email), '[]') from test_emails),
    'names', jsonb_build_object('principal', rc_set('school_principal'), 'supervisor', rc_set('club_supervisor'),
                                'coord46', rc_set('coord_4_6'), 'coord712', rc_set('coord_7_12')),
    'siteUrl', rc_set('site_url'),
    'allowedStudents', (select count(*) from allowed_students), 'allowedTeachers', (select count(*) from allowed_teachers));
end $$;

create or replace function saveadminsettings(a jsonb) returns boolean language plpgsql security definer set search_path = public as $$
declare sup text[] := rc_list(a ->> 'supervisors'); tst text[] := rc_list(a ->> 'tests');
begin
  perform rc_need_owner();
  if exists (select 1 from unnest(sup) x where rc_is_student_email(x)) then raise exception 'لا يمكن تعيين بريد طالب مشرفًا'; end if;
  delete from supervisors; insert into supervisors select x from unnest(sup) x where rc_is_school_email(x) and not rc_is_owner(x);
  delete from test_emails; insert into test_emails select x from unnest(tst) x where rc_is_student_email(x);
  if a ? 'names' then
    perform rc_put('school_principal', rc_clean(a -> 'names' ->> 'principal', 80));
    perform rc_put('club_supervisor', rc_clean(a -> 'names' ->> 'supervisor', 80));
    perform rc_put('coord_4_6', rc_clean(a -> 'names' ->> 'coord46', 80));
    perform rc_put('coord_7_12', rc_clean(a -> 'names' ->> 'coord712', 80));
  end if;
  if a ? 'siteUrl' then perform rc_put('site_url', rc_clean(a ->> 'siteUrl', 300)); end if;
  if a ? 'allowedStudents' then   -- قائمة كاملة تستبدل القديمة (فارغة = السماح لكل طلاب المدرسة)
    delete from allowed_students;
    insert into allowed_students select x from unnest(rc_list(a ->> 'allowedStudents')) x where rc_is_student_email(x);
  end if;
  if a ? 'allowedTeachers' then
    delete from allowed_teachers;
    insert into allowed_teachers select x from unnest(rc_list(a ->> 'allowedTeachers')) x where rc_is_school_email(x) and not rc_is_student_email(x);
  end if;
  return true;
end $$;

/* ---------- جلسات النقاش ---------- */
create or replace function getsessions() returns jsonb language plpgsql stable security definer set search_path = public as $$
declare w jsonb := rc_reviewer();
begin
  return jsonb_build_object(
    'sections', case when jsonb_typeof(w -> 'sections') = 'array' then w -> 'sections'
                else (select coalesce(jsonb_agg(section order by sort, section), '[]') from sections) end,
    'list', (select coalesce(jsonb_agg(jsonb_build_object('id', id, 'date', to_char(session_date, 'YYYY/MM/DD'), 'section', section,
      'book', book, 'count', count, 'notes', notes, 'by', by_name) order by created_at desc), '[]') from sessions where rc_can(w, section)));
end $$;

create or replace function addsession(a jsonb) returns boolean language plpgsql security definer set search_path = public as $$
declare w jsonb := rc_reviewer(); sec text := rc_clean(a ->> 'section', 30); bk text := rc_clean(a ->> 'book', 150);
  n int; d date;
begin
  if sec = '' or not rc_can(w, sec) then raise exception 'اختر شعبة من شعبك'; end if;
  if bk = '' then raise exception 'اكتب اسم الكتاب أو القصة'; end if;
  begin n := (a ->> 'count')::int; exception when others then n := 0; end;
  if coalesce(n, 0) <= 0 then raise exception 'اكتب عدد الحضور'; end if;
  if coalesce(a ->> 'date', '') !~ '^\d{4}-\d{2}-\d{2}$' then raise exception 'اختر تاريخ الجلسة'; end if;
  d := (a ->> 'date')::date;
  insert into sessions(session_date, section, book, count, notes, by_name, by_email)
    values (d, sec, bk, n, rc_clean(a ->> 'notes', 1500),
            case when w ->> 'role' = 'admin' then 'المشرف (' || (w ->> 'email') || ')' else w ->> 'name' end, w ->> 'email');
  if w ->> 'role' = 'teacher' then perform rc_check_teacher(w ->> 'email'); end if;
  return true;
end $$;

create or replace function deletesession(a jsonb) returns boolean language plpgsql security definer set search_path = public as $$
declare w jsonb := rc_reviewer(); s sessions;
begin
  select * into s from sessions where id = a #>> '{}';
  if not found then raise exception 'لم يُعثر على الجلسة'; end if;
  if w ->> 'role' <> 'admin' and s.by_email <> w ->> 'email' then raise exception 'تحذف الجلسات التي سجّلتها فقط'; end if;
  delete from sessions where id = s.id;
  return true;
end $$;

/* ---------- الشعبة الأنشط ---------- */
create or replace function rc_top_section(f timestamptz, t timestamptz) returns jsonb language sql stable security definer set search_path = public as $$
  with pts as (
    select section, case when rc_is_summary(title) then 15 else 10 end p from submissions
      where status = 'معتمد' and approved_at >= f and approved_at < t and name not like '%(تجريبي)%'
    union all select section, 5 from sessions where created_at >= f and created_at < t),
  top as (select section, sum(p)::int points from pts group by section order by 2 desc, 1 limit 1)
  select jsonb_build_object('section', section, 'points', points,
    'teacher', coalesce((select rc_with_a(name) from teachers where status = 'مفعّل' and top.section = any(sections) order by created_at limit 1), ''))
  from top
$$;

create or replace function gettopsection() returns jsonb language sql stable security definer set search_path = public as $$
  select rc_top_section(date_trunc('month', now() at time zone 'Asia/Dubai') at time zone 'Asia/Dubai', now() + interval '1 day')
$$;

/* ---------- الشهادات ---------- */
create or replace function getcert(a jsonb) returns jsonb language plpgsql stable security definer set search_path = public as $$
declare c certs; m jsonb := rc_me(); L jsonb; sample boolean := (a #>> '{}') = 'sample';
begin
  if sample then
    perform rc_need_admin();
    c := row('NRC-نموذج', now(), 'student', 2, '', 'أحمد سالم الكعبي', 'القارئ الذهبي', 'الصف العاشر · الشعبة 10C', 'أ. معلم الشعبة', 'معلم الصف', null)::certs;
  else
    select * into c from certs where no = a #>> '{}';
    if not found then raise exception 'لم يُعثر على الشهادة'; end if;
    if c.email <> m ->> 'email' and not (m ->> 'admin')::boolean then raise exception 'هذه الشهادة ليست لك'; end if;
  end if;
  L := rc_levels(c.kind) -> c.level;
  return jsonb_build_object('no', c.no, 'date', to_char(c.created_at at time zone 'Asia/Dubai', 'YYYY/MM/DD'), 'kind', c.kind,
    'levelKey', L ->> 'key', 'levelName', L ->> 'name', 'name', c.name, 'sub', c.sub,
    'sigs', jsonb_build_array(
      jsonb_build_array(coalesce(c.sig1, ''), coalesce(c.sig1_title, '')),
      jsonb_build_array(coalesce(nullif(rc_set('club_supervisor'), ''), 'د. عبدالحفيظ طه جمعه'), 'مشرف نادي القراءة'),
      jsonb_build_array(coalesce(nullif(rc_set('school_principal'), ''), 'أ. أحلام أبو راضي'), 'مديرة المدرسة')));
end $$;

/* ---------- الملخصات المجدولة (يشغّلها pg_cron، لا تستدعيها الواجهة) ---------- */
create or replace function rc_daily_digest() returns void language plpgsql security definer set search_path = public as $$
declare f timestamptz := now() - interval '24 hours'; t teachers; lst text; n int;
  ns int; ng int; npt int; nps int; b text;
begin
  for t in select * from teachers where status = 'مفعّل' loop
    select count(*), string_agg('<li>' || rc_esc(name) || ' (<span dir="ltr">' || rc_esc(section) || '</span>) – ' || rc_esc(title) || ' – محطة ' || rc_esc(station) || '</li>', '' order by created_at)
      into n, lst from submissions where created_at >= f and section = any(t.sections) and name not like '%(تجريبي)%';
    if n > 0 then
      perform rc_notify(t.email, '📨 طلابك يواصلون رحلتهم: ' || rc_count_ar(n, 'إنجاز جديد', 'إنجازان جديدان', 'إنجازات جديدة', 'إنجازًا جديدًا') || ' بانتظار ختمك',
        '<p>' || rc_teacher_title(t.name) || '،</p><p>رفع طلاب شعبك خلال آخر 24 ساعة:</p><ul>' || lst
        || '</ul><p>مراجعتك اليوم تعني ختمًا جديدًا في جواز طالب، ودفعة جديدة لشغفه بالقراءة عن وطنه. وكل مراجعة تضيف نقطتين إلى رصيدك.</p>', 'افتح بوابة المعلم');
    end if;
  end loop;
  select count(*) into n from submissions where created_at >= f and name not like '%(تجريبي)%';
  select count(*) into ns from sessions where created_at >= f;
  select count(*) into ng from gallery where created_at >= f;
  select count(*) into npt from teachers where status = 'بانتظار الموافقة';
  select count(*) into nps from submissions where status in ('قيد المراجعة', 'مرشح للاعتماد');
  if n + ns + ng + npt = 0 then return; end if;
  b := '<p>ملخص النادي لآخر 24 ساعة:</p><ul><li>إنجازات جديدة: <b>' || n || '</b> (وإجمالي ما ينتظر المراجعة: ' || nps || ')</li>'
    || '<li>جلسات نقاش مسجّلة: <b>' || ns || '</b></li><li>عناصر جديدة في المعرض: <b>' || ng || '</b></li>'
    || '<li>معلمون ينتظرون التفعيل: <b>' || npt || '</b></li></ul>';
  if ns > 0 then
    b := b || '<p><b>جلسات النقاش:</b></p><ul>' || (select string_agg('<li>' || rc_esc(by_name) || ' – <span dir="ltr">' || rc_esc(section)
      || '</span> – «' || rc_esc(book) || '» – ' || count || ' طالبًا</li>', '') from sessions where created_at >= f) || '</ul>';
  end if;
  if npt > 0 then
    b := b || '<p><b>بانتظار التفعيل:</b> ' || (select string_agg(rc_esc(name), '، ') from teachers where status = 'بانتظار الموافقة') || '</p>';
  end if;
  perform rc_notify(rc_admins(), '📊 ملخص نادي القراءة اليومي', b, 'افتح بوابة المشرف');
end $$;

create or replace function rc_monthly_digest() returns void language plpgsql security definer set search_path = public as $$
declare
  t0 timestamp := date_trunc('month', now() at time zone 'Asia/Dubai');
  f timestamptz := (t0 - interval '1 month') at time zone 'Asia/Dubai'; t timestamptz := t0 at time zone 'Asia/Dubai';
  mname text := to_char(t0 - interval '1 month', 'MM/YYYY'); top jsonb := rc_top_section(f, t);
  tc teachers; nsub int; nok int; nst int; nses int; lv int[]; o jsonb;
begin
  for tc in select * from teachers where status = 'مفعّل' loop
    select count(*), count(*) filter (where status = 'معتمد'), count(distinct email) into nsub, nok, nst
      from submissions where created_at >= f and created_at < t and section = any(tc.sections);
    select count(*) into nses from sessions where by_email = tc.email and created_at >= f and created_at < t;
    select array[count(*) filter (where l = 0), count(*) filter (where l = 1), count(*) filter (where l = 2), count(*) filter (where l = 3)] into lv
      from (select (rc_student_score(email) ->> 'level')::int l from students where section = any(tc.sections)) x;
    o := rc_teacher_score(tc.email);
    perform rc_notify(tc.email, '📅 حصاد شهر ' || mname || ' في نادي القراءة',
      '<p>' || rc_teacher_title(tc.name) || '،</p><p>هذا حصاد طلابك خلال الشهر الماضي:</p><ul>'
      || '<li>إنجازات مرفوعة: <b>' || nsub || '</b> (المعتمد منها: ' || nok || ')</li><li>طلاب شاركوا: <b>' || nst || '</b></li>'
      || '<li>جلسات نقاش سجّلتها: <b>' || nses || '</b></li>'
      || '<li>مستويات طلابك حتى الآن: 🥉 ' || lv[1] || ' · 🥈 ' || lv[2] || ' · 🥇 ' || lv[3] || ' · 💎 ' || lv[4] || '</li></ul>'
      || '<p>رصيدك: <b>' || (o ->> 'points') || ' نقطة</b>، ومستواك ' || (o ->> 'medal') || ' <b>' || (o ->> 'levelName') || '</b>. '
      || case when jsonb_typeof(o -> 'next') = 'object' then 'بقيت ' || (o -> 'next' ->> 'need') || ' نقطة على ' || (o -> 'next' ->> 'medal') || ' ' || (o -> 'next' ->> 'name') || '.' else '' end || '</p>'
      || case when top is null then '' else '<p>🏆 الشعبة الأنشط الشهر الماضي: <b dir="ltr">' || rc_esc(top ->> 'section') || '</b>'
         || case when top ->> 'teacher' <> '' then ' مع ' || rc_esc(top ->> 'teacher') else '' end || '.'
         || case when (top ->> 'section') = any(tc.sections) then ' مبارك لك ولطلابك! 🎉' else ' هل تكون شعبتك الأنشط هذا الشهر؟' end || '</p>' end,
      'افتح بوابة المعلم');
  end loop;
  if top is not null then
    perform rc_notify(rc_admins(), '🏆 الشعبة الأنشط في شهر ' || mname, '<p>الشعبة الأنشط في نادي القراءة خلال الشهر الماضي: <b dir="ltr">'
      || rc_esc(top ->> 'section') || '</b>' || case when top ->> 'teacher' <> '' then ' مع ' || rc_esc(top ->> 'teacher') else '' end
      || ' برصيد ' || (top ->> 'points') || ' نقطة.</p>', 'افتح بوابة المشرف');
  end if;
end $$;

/* ---------- أدوات صلاحيات مخزن الملفات (تستخدمها storage.sql) ---------- */
create or replace function rc_storage_reviewer() returns boolean language plpgsql stable security definer set search_path = public as $$
begin perform rc_reviewer(); return true; exception when others then return false; end $$;
create or replace function rc_storage_admin() returns boolean language sql stable security definer set search_path = public as
$$ select coalesce((rc_me() ->> 'admin')::boolean, false) $$;

-- =====================================================================
--  الصلاحيات: المتصفح يستدعي الوظائف العامة فقط، وبعد تسجيل الدخول فقط
-- =====================================================================
revoke all on all functions in schema public from public, anon, authenticated;
grant execute on function
  getsections(), whoami(), startpreview(jsonb), stoppreview(), joinclub(jsonb), submitachievement(jsonb),
  getstudent(), getmyscore(), registerteacher(jsonb), listteachers(), setsupervisor(jsonb, jsonb),
  setteacherstatus(jsonb, jsonb), listsubmissions(), reviewsubmission(jsonb, jsonb, jsonb), getstats(),
  addmedia(jsonb), listgallery(), deletemedia(jsonb), getadminsettings(), saveadminsettings(jsonb),
  getsessions(), addsession(jsonb), deletesession(jsonb), gettopsection(), getcert(jsonb),
  rc_real(), rc_storage_reviewer(), rc_storage_admin()
to authenticated;

-- وظيفة إرسال البريد (send-mail) تقرأ صندوق الصادر بصلاحية service_role
grant usage on schema public to service_role;
grant select, update on outbox to service_role;

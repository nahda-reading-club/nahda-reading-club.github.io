-- =====================================================================
--  مخزن الملفات (بديل مجلدات Google Drive)
--  شغّله بعد schema.sql في SQL Editor.
--  submissions: ملفات إنجازات الطلاب (يرفع الطالب في مجلد باسم بريده، ويقرأ المعلمون والمشرفون)
--  gallery: صور وفيديو المعرض (يرفع المشرفون فقط، ويشاهد كل حسابات المدرسة)
-- =====================================================================
insert into storage.buckets (id, name, public, file_size_limit)
values ('submissions', 'submissions', false, 10485760), ('gallery', 'gallery', false, 52428800)
on conflict (id) do update set file_size_limit = excluded.file_size_limit, public = false;

drop policy if exists "rc submissions upload" on storage.objects;
drop policy if exists "rc submissions read" on storage.objects;
drop policy if exists "rc gallery read" on storage.objects;
drop policy if exists "rc gallery write" on storage.objects;
drop policy if exists "rc gallery delete" on storage.objects;

create policy "rc submissions upload" on storage.objects for insert to authenticated
  with check (bucket_id = 'submissions' and (storage.foldername(name))[1] = public.rc_real()
              and public.rc_real() ~ '^[^@\s]+@nahdaschools\.com$');

create policy "rc submissions read" on storage.objects for select to authenticated
  using (bucket_id = 'submissions' and ((storage.foldername(name))[1] = public.rc_real() or public.rc_storage_reviewer()));

create policy "rc gallery read" on storage.objects for select to authenticated
  using (bucket_id = 'gallery' and public.rc_real() ~ '^[^@\s]+@nahdaschools\.com$');

create policy "rc gallery write" on storage.objects for insert to authenticated
  with check (bucket_id = 'gallery' and public.rc_storage_admin());

create policy "rc gallery delete" on storage.objects for delete to authenticated
  using (bucket_id = 'gallery' and public.rc_storage_admin());

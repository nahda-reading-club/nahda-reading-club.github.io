/**
 * تصدير بيانات نادي القراءة من Google Sheets إلى ملف SQL لـ Supabase.
 *
 * الطريقة:
 *  1) افتح مشروع Apps Script القديم ← أضف ملفًا جديدًا (+ ← Script) باسم Export والصق هذا الكود.
 *  2) اختر الدالة exportToSupabase من القائمة أعلى المحرر ← Run.
 *  3) افتح «السجل» (Execution log): سيظهر رابط ملف import.sql في مجلد المنصة على Drive.
 *  4) افتح الملف وانسخ محتواه كاملًا والصقه في Supabase ← SQL Editor ← Run.
 * يمكن تكراره بأمان: لا يكرر صفًا موجودًا.
 * ملاحظة: الملفات المرفقة القديمة تبقى روابط Google Drive داخل المنصة الجديدة.
 */
function exportToSupabase() {
  const ss = SpreadsheetApp.getActiveSpreadsheet();
  const rows = function (name) { const sh = ss.getSheetByName(name); return sh ? sh.getDataRange().getValues().slice(1) : []; };
  const q = function (v) { return v === null || v === undefined || v === '' ? 'null' : "'" + String(v).replace(/'/g, "''") + "'"; };
  const s = function (v) { return v instanceof Date ? Utilities.formatDate(v, 'Asia/Dubai', 'yyyy/MM/dd HH:mm') : String(v == null ? '' : v).trim(); };
  const ts = function (v) {
    if (v instanceof Date) return q(Utilities.formatDate(v, 'UTC', "yyyy-MM-dd'T'HH:mm:ss'Z'"));
    const d = new Date(String(v)); return isNaN(d) || !v ? 'null' : q(Utilities.formatDate(d, 'UTC', "yyyy-MM-dd'T'HH:mm:ss'Z'"));
  };
  const day = function (v) { return v instanceof Date ? q(Utilities.formatDate(v, 'Asia/Dubai', 'yyyy-MM-dd')) : q(String(v).trim().replace(/\//g, '-').slice(0, 10)); };
  const lo = function (v) { return s(v).toLowerCase(); };
  const arr = function (v) { const a = s(v).split(',').map(function (x) { return x.trim(); }).filter(String); return "array[" + a.map(q).join(',') + "]::text[]"; };
  const out = ['-- بيانات منقولة من Google Sheets بتاريخ ' + Utilities.formatDate(new Date(), 'Asia/Dubai', 'yyyy/MM/dd HH:mm'), 'begin;'];
  const add = function (sql) { out.push(sql + ' on conflict do nothing;'); };

  // الإعدادات
  const set = {}; rows('الإعدادات').forEach(function (r) { set[s(r[0])] = s(r[1]); });
  out.push("update settings set value = " + q(Session.getEffectiveUser().getEmail().toLowerCase()) + " where key = 'owner_email';");
  [['مديرة المدرسة', 'school_principal'], ['مشرف النادي', 'club_supervisor'], ['منسق العربية 4-6', 'coord_4_6'], ['منسق العربية 7-12', 'coord_7_12']]
    .forEach(function (p) { if (set[p[0]]) out.push('update settings set value = ' + q(set[p[0]]) + ' where key = ' + q(p[1]) + ';'); });
  const list = function (t) { return String(t || '').split(/[,،\s]+/).map(function (x) { return x.trim().toLowerCase(); }).filter(String); };
  const owner = Session.getEffectiveUser().getEmail().toLowerCase();
  list(set['بريد المشرف']).filter(function (e) { return e !== owner; }).forEach(function (e) { add('insert into supervisors values (' + q(e) + ')'); });
  list(set['بريد تجريبي']).forEach(function (e) { add('insert into test_emails values (' + q(e) + ')'); });

  // الشعب
  const secs = rows('الشعب').filter(function (r) { return r[2]; });
  if (secs.length) {
    out.push('delete from sections where not exists (select 1 from students) and not exists (select 1 from teachers);');
    secs.forEach(function (r, i) { add('insert into sections(track, grade, section, sort) values (' + q(s(r[0])) + ',' + q(s(r[1])) + ',' + q(s(r[2])) + ',' + (i + 1) + ')'); });
  }
  // البريد المسموح
  rows('البريد المسموح').forEach(function (r) {
    if (lo(r[0])) add('insert into allowed_students values (' + q(lo(r[0])) + ')');
    if (lo(r[1])) add('insert into allowed_teachers values (' + q(lo(r[1])) + ')');
  });
  // الطلاب: التاريخ، الاسم، المسار، الصف، الشعبة، المجال، الاقتراح، البريد
  rows('الطلاب').forEach(function (r) {
    if (!lo(r[7])) return;
    add('insert into students(email, name, track, grade, section, interest, idea, created_at) values (' + [q(lo(r[7])), q(s(r[1])), q(s(r[2])), q(s(r[3])), q(s(r[4])), q(s(r[5])), q(s(r[6])), ts(r[0])].join(',') + ')');
  });
  // المعلمون
  rows('المعلمون').forEach(function (r) {
    if (!lo(r[1])) return;
    add('insert into teachers(email, name, sections, status, created_at) values (' + [q(lo(r[1])), q(s(r[0])), arr(r[2]), q(s(r[3]) || 'بانتظار الموافقة'), ts(r[4])].join(',') + ')');
  });
  // الإنجازات
  rows('الإنجازات').forEach(function (r) {
    if (!s(r[0]) || !lo(r[14])) return;
    add('insert into submissions(id, created_at, name, track, grade, section, station, title, descr, file_url, status, note, approved_at, reviewer, email) values ('
      + [q(s(r[0])), ts(r[1]), q(s(r[2])), q(s(r[3])), q(s(r[4])), q(s(r[5])), q(s(r[6])), q(s(r[7])), q(s(r[8])), q(s(r[9])), q(s(r[10]) || 'قيد المراجعة'), q(s(r[11])), ts(r[12]), q(s(r[13])), q(lo(r[14]))].join(',') + ')');
  });
  // جلسات النقاش
  rows('جلسات النقاش').forEach(function (r) {
    if (!s(r[0])) return;
    add('insert into sessions(id, session_date, section, book, count, notes, by_name, by_email, created_at) values ('
      + [q(s(r[0])), day(r[1]), q(s(r[2])), q(s(r[3])), parseInt(r[4], 10) || 0, q(s(r[5])), q(s(r[6])), q(lo(r[7])), ts(r[8])].join(',') + ')');
  });
  // المعرض (يبقى رابطًا إلى Drive)
  rows('المعرض').forEach(function (r) {
    if (!s(r[0]) || !s(r[5])) return;
    add('insert into gallery(id, created_at, type, title, descr, url, uploaded_by) values ('
      + [q(s(r[0])), ts(r[1]), q(s(r[2]) || 'صورة'), q(s(r[3])), q(s(r[4])), q('https://drive.google.com/file/d/' + s(r[5]) + '/view'), q(lo(r[6]))].join(',') + ')');
  });
  // الشهادات الصادرة (تبقى روابط PDF على Drive)
  rows('الشهادات').forEach(function (r) {
    if (!s(r[0]) || !lo(r[3])) return;
    const kl = s(r[2]).split(':');
    add('insert into certs(no, created_at, kind, level, email, name, level_name, url) values ('
      + [q(s(r[0])), ts(r[1]), q(kl[0] || 'student'), parseInt(kl[1], 10) || 0, q(lo(r[3])), q(s(r[4])), q(s(r[5])), q(s(r[6]))].join(',') + ')');
  });
  out.push('commit;');

  const folderId = set['مجلد المنصة'];
  const dir = folderId ? DriveApp.getFolderById(folderId) : DriveApp.getRootFolder();
  const file = dir.createFile('import.sql', out.join('\n'), 'text/plain');
  console.log('تم التصدير: ' + (out.length - 3) + ' سطرًا. افتح الملف: ' + file.getUrl());
  return file.getUrl();
}

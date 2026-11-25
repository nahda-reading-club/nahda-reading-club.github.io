-- =====================================================================
--  الإشعارات المجدولة (اختياري – بعد تفعيل البريد)
--  1) Database ← Extensions: فعّل pg_cron و pg_net
--  2) استبدل PROJECT_REF و SERVICE_ROLE_KEY أدناه، ثم شغّل الملف في SQL Editor
-- =====================================================================
select cron.unschedule(jobname) from cron.job where jobname in ('rc-daily', 'rc-monthly', 'rc-mail');

-- الملخص اليومي الساعة 2 ظهرًا بتوقيت الإمارات (10:00 UTC)
select cron.schedule('rc-daily', '0 10 * * *', $$ select public.rc_daily_digest() $$);
-- حصاد الشهر أول كل شهر الساعة 9 صباحًا بتوقيت الإمارات (05:00 UTC)
select cron.schedule('rc-monthly', '0 5 1 * *', $$ select public.rc_monthly_digest() $$);
-- إرسال صندوق الصادر كل 5 دقائق
select cron.schedule('rc-mail', '*/5 * * * *', $$
  select net.http_post(
    url := 'https://PROJECT_REF.supabase.co/functions/v1/send-mail',
    headers := jsonb_build_object('Authorization', 'Bearer SERVICE_ROLE_KEY', 'Content-Type', 'application/json'),
    body := '{}'::jsonb)
$$);

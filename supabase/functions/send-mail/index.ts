// يرسل رسائل صندوق الصادر (outbox) عبر Brevo. يُشغَّل كل 5 دقائق من pg_cron (انظر cron.sql).
// الأسرار المطلوبة (Edge Functions ← Secrets): BREVO_API_KEY, MAIL_FROM (بريد مُوثّق في Brevo)
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.45.4';

Deno.serve(async () => {
  const db = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
  const key = Deno.env.get('BREVO_API_KEY'), from = Deno.env.get('MAIL_FROM');
  if (!key || !from) return new Response('BREVO_API_KEY / MAIL_FROM missing', { status: 500 });
  const { data: rows, error } = await db.from('outbox').select('*').is('sent_at', null).is('error', null).order('id').limit(40);
  if (error) return new Response(error.message, { status: 500 });
  let sent = 0;
  for (const r of rows ?? []) {
    const to = String(r.to_emails).split(',').filter(Boolean).map((email: string) => ({ email }));
    const res = await fetch('https://api.brevo.com/v3/smtp/email', {
      method: 'POST',
      headers: { 'api-key': key, 'content-type': 'application/json', accept: 'application/json' },
      body: JSON.stringify({ sender: { name: 'نادي القراءة الإماراتي', email: from }, to: to.length > 1 ? [{ email: from }] : to,
        ...(to.length > 1 ? { bcc: to } : {}), subject: r.subject, htmlContent: r.html }),
    });
    if (res.ok) { sent++; await db.from('outbox').update({ sent_at: new Date().toISOString() }).eq('id', r.id); }
    else await db.from('outbox').update({ error: (await res.text()).slice(0, 500) }).eq('id', r.id);
  }
  return new Response(JSON.stringify({ sent }), { headers: { 'content-type': 'application/json' } });
});

# منصة نادي القراءة الإماراتي – الإصدار المستقل عن Google Apps Script

«رحلة قارئ… حكاية وطن» – مدرسة النهضة الوطنية للبنين

- **الواجهة:** `index.html` و `config.js` تُنشر على GitHub Pages.
- **الخلفية:** Supabase (قاعدة بيانات + تسجيل دخول + تخزين ملفات) بدل Google Sheets و Drive و Code.gs.
- **الشهادات:** تُرسم في المتصفح ويحفظها صاحبها PDF، بدل Google Slides.

| الملف | ماذا يفعل |
|---|---|
| `index.html` | المنصة كاملة (نفس الشكل والمحتوى القديم) |
| `config.js` | رابط مشروع Supabase ومفتاحه، وطريقة الدخول |
| `supabase/schema.sql` | الجداول وكل وظائف الخادم (بديل Code.gs) |
| `supabase/storage.sql` | مخزن ملفات الإنجازات والمعرض وصلاحياته |
| `supabase/cron.sql` | الملخص اليومي والشهري وإرسال البريد (اختياري) |
| `supabase/functions/send-mail` | وظيفة إرسال البريد عبر Brevo (اختياري) |
| `migration/Export.gs` | ينقل البيانات القديمة من Google Sheets |

---

## الخطوة 1: مشروع Supabase (10 دقائق)

1. ادخل [supabase.com/dashboard](https://supabase.com/dashboard) واختر **Continue with GitHub**.
2. اضغط **New project**: الاسم `reading-club`، اكتب كلمة مرور لقاعدة البيانات واحفظها عندك، والمنطقة **Frankfurt** أو **Mumbai**، ثم **Create**. انتظر دقيقتين.
3. من القائمة اليسرى افتح **SQL Editor** ← **New query**:
   - افتح الملف `supabase/schema.sql` وانسخه كله والصقه.
   - ابحث عن السطر `ضع_بريد_الأدمن_هنا@nahdaschools.com` واكتب مكانه بريدك المدرسي.
   - اضغط **Run**. يجب أن تظهر كلمة Success.
   - افتح استعلامًا جديدًا، والصق `supabase/storage.sql`، ثم **Run**.
4. افتح **Project Settings** ← **API** (أو **Data API**) وانسخ:
   - **Project URL** (مثل `https://abcd.supabase.co`)
   - مفتاح **anon public**
   ثم ضعهما في `config.js` مكان `https://XXXX.supabase.co` و `ضع_مفتاح_anon_هنا`.

## الخطوة 2: النشر على GitHub (5 دقائق)

1. افتح [github.com/new](https://github.com/new): الاسم `reading-club`، واختر **Public**، ثم **Create repository**.
2. اضغط الرابط **uploading an existing file**، واسحب إليه كل محتوى هذا المجلد (بما فيه `index.html` و `config.js` بعد تعديله)، ثم **Commit changes**.
3. افتح **Settings** ← **Pages**، ومن **Branch** اختر `main` ثم `/ (root)` ← **Save**.
4. بعد دقيقة أو اثنتين يظهر رابط المنصة:
   `https://drabdulhafizjumah-crypto.github.io/reading-club/`

## الخطوة 3: تسجيل الدخول بحساب المدرسة (15 دقيقة، مرة واحدة)

1. افتح [console.cloud.google.com](https://console.cloud.google.com) بحسابك المدرسي، وأنشئ مشروعًا باسم `reading-club`.
2. **APIs & Services** ← **OAuth consent screen**: اختر **Internal** (فلا يدخل إلا أصحاب حسابات nahdaschools.com)، واكتب اسم التطبيق «نادي القراءة الإماراتي» وبريدك، ثم احفظ.
3. **Credentials** ← **Create credentials** ← **OAuth client ID** ← النوع **Web application**.
   في **Authorized redirect URIs** أضف: `https://مشروعك.supabase.co/auth/v1/callback` ← **Create**. انسخ **Client ID** و **Client secret**.
4. في Supabase: **Authentication** ← **Sign In / Providers** ← **Google**: فعّله والصق الرقمين ← **Save**.
5. في Supabase: **Authentication** ← **URL Configuration**:
   - **Site URL**: رابط المنصة من الخطوة 2.
   - **Redirect URLs**: أضف الرابط نفسه.

> إن منعت إدارة المدرسة إنشاء مشروع في Google Cloud، غيّر في `config.js` السطر `auth: 'google'` إلى `auth: 'otp'` (رمز يصل إلى البريد)، وسنحتاج حينها ربط خدمة بريد في Supabase.

## الخطوة 4: نقل البيانات القديمة

1. افتح محرر Apps Script القديم، وأضف ملفًا جديدًا باسم `Export`، والصق فيه `migration/Export.gs`.
2. اختر الدالة `exportToSupabase` ← **Run**، ووافق على الأذونات.
3. سيظهر في السجل رابط ملف `import.sql` في مجلد المنصة على Drive. افتحه، وانسخ محتواه، والصقه في Supabase ← SQL Editor ← **Run**.

ينقل: الطلاب، والمعلمين وحالاتهم، والإنجازات، وجلسات النقاش، والمعرض، والشهادات الصادرة، والمشرفين، والقوائم المسموحة، والشعب، وأسماء التوقيعات.
الملفات المرفقة القديمة وصور المعرض القديمة تبقى روابط إلى Google Drive وتعمل كما هي.

## الخطوة 5 (اختيارية): رسائل البريد

المنصة تكتب كل الرسائل (الاعتماد، والمستويات، والملخص اليومي والشهري) في جدول `outbox`. لإرسالها فعلًا:
1. أنشئ حسابًا مجانيًا في [brevo.com](https://www.brevo.com) (300 رسالة يوميًا)، ووثّق بريد المرسل، وأنشئ **API key**.
2. في Supabase: **Edge Functions** ← أنشئ وظيفة باسم `send-mail` والصق `supabase/functions/send-mail/index.ts`.
   ثم **Edge Functions** ← **Secrets**: أضف `BREVO_API_KEY` و `MAIL_FROM`.
3. **Database** ← **Extensions**: فعّل `pg_cron` و `pg_net`، ثم شغّل `supabase/cron.sql` بعد وضع رقم مشروعك ومفتاح service_role.

## بعد التشغيل

- ادخل المنصة ببريدك، ومن **بوابة المشرف** ← **إعدادات المنصة** ضع رابط المنصة الجديد (يظهر زرًا في رسائل البريد)، وراجع أسماء التوقيعات، واضغط **معاينة شهادة نموذجية**.
- الأدمن هو صاحب البريد المكتوب في `owner_email`، ويُغيَّر من Supabase ← Table Editor ← settings.

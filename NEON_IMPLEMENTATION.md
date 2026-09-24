# نظام ضياء المستقبل — تنفيذ Neon

تم اعتماد Neon PostgreSQL بدل Supabase بالكامل.

## المرحلة الحالية

الملف `database/migrations/0001_neon_core.sql` ينشئ:

- الأدوار الأساسية: المدير، المالية، شؤون الطلاب، الموارد البشرية، والأرشيف.
- الفروع مع حالة التفعيل والأرشفة.
- ملفات المستخدمين والصلاحيات وربط المستخدم بالفرع.
- السنوات الدراسية مع تاريخ البداية والنهاية.
- القيود والفهارس و`updated_at` triggers.
- PostgreSQL Row Level Security لعزل بيانات الفروع والعمليات الإدارية.

## تشغيل migration

1. أنشئ قاعدة Neon PostgreSQL.
2. استخدم رابط الاتصال من Neon في `DATABASE_URL` كـ Secret على Replit أو Vercel.
3. شغّل الملف من Neon SQL Editor أو عبر أداة migrations في المشروع.
4. لا تضع `DATABASE_URL` في المتصفح أو داخل ملفات Git.

```bash
psql "$DATABASE_URL" -f database/migrations/0001_neon_core.sql
```

## سياق الصلاحيات

قبل تنفيذ أي Server Action، يفتح الخادم transaction ويضع سياق المستخدم الذي تم التحقق منه عبر Auth.js:

```sql
BEGIN;
SET LOCAL app.user_id = 'USER_PROFILE_UUID';
SET LOCAL app.role_code = 'admin';
SET LOCAL app.branch_id = 'BRANCH_UUID';
-- الاستعلام أو العملية هنا
COMMIT;
```

القيمة `DATABASE_URL` لا تصل إلى Client Components ولا إلى المتصفح. إخفاء عناصر الواجهة ليس طبقة الأمان الوحيدة؛ السياسات الموجودة في Neon تمنع الوصول غير المصرح به على مستوى قاعدة البيانات أيضًا.

## الخدمات المكملة

Neon يوفر PostgreSQL فقط. لذلك سيستخدم النظام:

- Auth.js للمصادقة والجلسات.
- Object Storage متوافق مع S3 للمستندات والمرفقات.
- Next.js Server Actions للتدقيق والتحقق وتنفيذ العمليات.

لن يتم استخدام Supabase أو SQLite أو LocalStorage أو بيانات Mock كمصدر للنظام.
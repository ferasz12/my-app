# Wazen Launch RSVP (حضور تدشين وازن)

تم إضافة:
- صفحة التسجيل: /attend
- لوحة الإدارة: /admin (Google Sign-In)

## خطوات التشغيل السريعة

1) فعّل تسجيل دخول Google في Firebase Auth:
Firebase Console > Authentication > Sign-in method > Google > Enable

2) حدّد بريد الإدارة المسموح (افتراضيًا):
functions/src/index.ts
LAUNCH_ADMIN_EMAILS = ["support@wazensapp.com"]

3) نشر الدوال:
cd functions
npm i
npm run build
cd ..
firebase deploy --only functions:registerLaunchAttendance,functions:listLaunchAttendees

4) نشر الاستضافة:
firebase deploy --only hosting

## ملاحظات
- التسجيل يتم عبر Cloud Function ولا توجد قراءة/كتابة مباشرة لمجموعة launch_attendees من الويب.
- يمكنك مشاهدة البيانات أيضًا من Firestore Console كأدمن.

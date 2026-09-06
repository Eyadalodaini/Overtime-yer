# طريقة رفع المشروع إلى GitHub وبناء APK

1. فك ضغط ملف المشروع على جهازك.
2. أنشئ Repository جديدًا في GitHub.
3. افتح المجلد المفكوك.
4. ارفع **محتويات المجلد كلها** إلى المستودع، وليس ملف ZIP.
5. تأكد أن `pubspec.yaml` و`lib/` و`.github/` ظاهرة في الصفحة الرئيسية للمستودع.
6. اضغط Commit changes.
7. افتح تبويب Actions.
8. اختر `Build Android APK`.
9. إذا لم يبدأ تلقائيًا، اختر Run workflow.
10. بعد نجاح البناء، افتح العملية الناجحة.
11. في أسفل الصفحة ستجد Artifacts.
12. نزّل `overtime-yER-release`.
13. فك ضغط الـ Artifact وستجد `app-release.apk`.

لا تحتاج إلى تشغيل build.sh إذا كنت تستخدم GitHub Actions.

ملاحظة: أول تشغيل قد يقوم Workflow بتجهيز ملفات Android الناقصة تلقائيًا بواسطة `flutter create .`.

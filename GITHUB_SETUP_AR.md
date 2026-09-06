# طريقة الرفع إلى GitHub وتشغيل بناء APK

## 1) فك الضغط
فك ضغط الملف على جهازك.

## 2) ارفع محتويات المشروع
أنشئ مستودعًا جديدًا على GitHub، ثم ارفع **محتويات المجلد** وليس ملف ZIP نفسه.

يجب أن ترى في جذر المستودع:
- `pubspec.yaml`
- `lib/`
- `.github/`
- `README.md`

وبداخل `.github/workflows/` يجب أن تجد:
`build-apk.yml`

## 3) لماذا لم يظهر Workflow سابقًا؟
تبويب Actions يعرض ملفات GitHub Actions الموجودة فعليًا داخل:
`.github/workflows/`

بعد رفع الملفات وعمل Commit/Push، افتح:
**Actions**

ستجد:
**Build Android APK**

إذا لم يظهر فورًا، حدّث الصفحة وتأكد أن الملف موجود في المستودع على الفرع `main` أو `master`.

## 4) تشغيل البناء
- افتح **Actions**
- اختر **Build Android APK**
- اضغط **Run workflow**
- اختر الفرع `main`
- اضغط **Run workflow**

## 5) تنزيل APK
بعد نجاح المهمة:
- افتح عملية التشغيل الناجحة
- في الأسفل ستجد **Artifacts**
- نزّل `overtime-yer-release`
- فك الضغط وستجد `app-release.apk`

## ملاحظة مهمة
لا تحتاج إلى تشغيل `build.sh` على جهازك. GitHub Actions يتولى إنشاء ملفات Android الناقصة، ثم تثبيت الاعتمادات وبناء APK.

## إذا ظهر خطأ في Analyze
افتح عملية الـ workflow وانسخ أول رسالة خطأ حمراء كاملة وأرسلها لي، وسأعدل المشروع بناءً عليها.

## إذا ظهر خطأ `MyApp isn't a class`
لا تقلق. النسخة المصححة من المشروع تمنع GitHub Actions من استبدال `lib/main.dart` عند إنشاء ملفات Android.
استخدم النسخة النهائية المرفقة، ثم ادفع التعديل إلى GitHub وأعد تشغيل الـWorkflow.

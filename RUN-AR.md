# تشغيل مشروع «azal» على جهازك

المشروع Flutter (Dart) مع Firebase. الملف المضغوط يحتوي الكود الكامل
بما فيه آخر إضافات الحسابات وميزانية المشاريع، وملف إعداد Firebase
لأندرويد `android/app/google-services.json`.

---

## 1) المتطلبات

1. **Flutter SDK** (الإصدار المستقر 3.x): https://docs.flutter.dev/get-started/install
2. **Android Studio** (أو Visual Studio Code مع إضافة Flutter).
3. **JDK 17** (يأتي مع Android Studio).
4. على الجهاز: `flutter doctor` ثم عالج أي ملاحظة (خصوصًا Android SDK).

## 2) فك الضغط وتجهيز الحزم

```bash
unzip azal-project.zip
cd project_mangment
flutter pub get
```

## 3) تشغيل التطبيق

```bash
# على محاكي أندرويد أو جهاز موصول بالـ USB مع USB Debugging
flutter devices
flutter run
```

## 4) بناء ملف APK لتنصيبه على هاتفك

```bash
flutter build apk --release
```

الملف الناتج:

```
build/app/outputs/flutter-apk/app-release.apk
```

انقل الملف إلى الهاتف وثبّته (اسم الحزمة `com.azal.azal` — راجع
`android/app/build.gradle.kts`). لبناء نسخة لكل معماريات الهاتف:

```bash
flutter build apk --release --split-per-abi
```

## 5) ملاحظات Firebase

- إعداد أندرويد موجود في `android/app/google-services.json`.
- إعداد Dart موجود في `lib/firebase_options.dart`.
- لأجهزة iOS تحتاج `ios/Runner/GoogleService-Info.plist` من لوحة
  Firebase (غير موجود حاليًا في المستودع)، ثم `flutter build ios`.
- قواعد Firestore الحالية في `firestore.rules` تسمح لكل مستخدم
  مسجّل بالقراءة والكتابة.

## 6) الاختبارات

```bash
flutter test
```

## 7) آخر الإضافات في هذا الإصدار

- شاشة **ميزانية المشاريع**: أصول وخصوم وحقوق ملكية وإيرادات
  ومصروفات لكل مشروع، وما يشمله كل قسم، ومعادلة التوازن.
- المحاسب المربوط بمشروع يرى ميزانية مشروعه فقط، والمدير المالي
  يرى كل المشاريع، والمحاسب غير المربوط لا يملك صلاحية الوصول.

المستندات التفصيلية في مجلد `docs/` (خصوصًا
`docs/الحسابات-والصندوق.md`).

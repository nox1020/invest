# Invest — مدیریت سرمایه و معاملات (Android / Flutter)

اپلیکیشن موبایل برای مدیریت دارایی، خرید/فروش، و صندوق طلا (وارد / خارج / موجودی).

ریپو: https://github.com/nox1020/invest

## نصب APK روی اندروید

### از GitHub Actions
1. به [Actions](https://github.com/nox1020/invest/actions) بروید.
2. آخرین اجرای موفق workflow با نام **Android APK** را باز کنید.
3. از بخش **Artifacts** فایل `invest-apk` را دانلود و از حالت فشرده خارج کنید.
4. `app-release.apk` را روی گوشی نصب کنید (مجوز «نصب از منابع ناشناس» لازم است).

### از Releases
اگر تگ `v*` ساخته شده باشد، از صفحه [Releases](https://github.com/nox1020/invest/releases) APK را بگیرید.

## قابلیت‌ها (v1)

- داشبورد: ارزش کل، سود سالانه تحقق‌یافته، طلای وارد/خارج/موجودی
- دارایی‌ها (افزودن / ویرایش قیمت)
- معاملات باز و بسته + خرید و فروش جزئی
- تنظیمات: تقویم جلالی/میلادی، ارز، تم دارک/روشن، API تتر و طلا
- کش قیمت و بروزرسانی دستی

## توسعه محلی

```bash
flutter pub get
flutter test
flutter run
flutter build apk --release
```

خروجی APK:

`build/app/outputs/flutter-apk/app-release.apk`

## معماری

- Flutter + Provider
- SQLite (`sqflite`)
- منطق دامنه هم‌تراز نسخهٔ دسکتاپ (لات باز/بسته، صندوق طلا)

## ApplicationId

`com.nox1020.invest`

// All samples are invented (fake amounts/accounts); no real SMS in this repo.
import 'package:flutter_test/flutter_test.dart';
import 'package:invest/domain/services/bank_sms_parser.dart';
import 'package:invest/ui/widgets/bank_sms_ui.dart';

void main() {
  final rx = DateTime(2026, 10, 25, 14, 30);
  BankSmsItem? p(String s, String b) => parseBankSms(s, b, rx);

  test('Mellat style: برداشت + مانده (rial→toman)', () {
    final r = p('+98999000111',
        'بانک ملت\nبرداشت: 1,250,000\nحساب: 123***45\nمانده: 8,400,000\n1405/08/03-14:22')!;
    expect(r.bank, 'بانک ملت');
    expect(r.toman, 125000);
    expect(r.balanceToman, 840000);
    expect(r.card, '45');
    expect(r.at, DateTime(2026, 10, 25, 14, 22));
    expect(r.lowConfidence, isFalse);
  });

  test('Melli style with Persian digits and مبلغ', () {
    final r = p('BMI',
        'بانک ملی ایران\nبرداشت از حساب\nمبلغ: ۵۰۰٬۰۰۰ ریال\nمانده: ۲٬۰۰۰٬۰۰۰\n۱۴۰۵/۰۸/۰۳ ۱۰:۱۵')!;
    expect(r.bank, 'بانک ملی');
    expect(r.toman, 50000);
    expect(r.balanceToman, 200000);
  });

  test('Saderat style minus amount (خرید)', () {
    final r =
        p('Saderat', 'صادرات\nخرید\n-750,000\nمانده 1,000,000\n0803-12:00')!;
    expect(r.toman, 75000);
    expect(r.balanceToman, 100000);
  });

  test('Pasargad style برداشت ... ریال, موجودی', () {
    final r = p('bpi',
        'پاسارگاد\nبرداشت 2,000,000 ریال\nموجودی 5,000,000\n1405/08/03 09:30')!;
    expect(r.bank, 'بانک پاسارگاد');
    expect(r.toman, 200000);
    expect(r.balanceToman, 500000);
  });

  test('Saman style انتقال with compact date', () {
    final r = p('Saman',
        'بانک سامان\nانتقال وجه\n-3,000,000\nمانده:10,000,000\n14050803 18:40')!;
    expect(r.toman, 300000);
    expect(r.at, DateTime(2026, 10, 25, 18, 40));
  });

  test('Tejarat style card mask and colon', () {
    final r =
        p('tejarat', 'تجارت\nکارت 6037**1234\nبرداشت:120,000\nمانده:900,000')!;
    expect(r.card, '1234');
    expect(r.toman, 12000);
  });

  test('Ayandeh style trailing minus', () {
    final r = p('Ayandeh', 'آینده\nمبلغ 45,000- ریال\nمانده 99,000')!;
    expect(r.toman, 4500);
    expect(r.balanceToman, 9900);
  });

  test('amount in toman is kept as is', () {
    expect(p('x', 'برداشت 20,000 تومان')!.toman, 20000);
  });

  test('deposit, OTP and ads are ignored', () {
    expect(p('Mellat', 'بانک ملت\nواریز: 1,000,000\nمانده: 3,000,000'), isNull);
    expect(p('Mellat', 'رمز پویا: 123456 مبلغ خرید 1,000,000'), isNull);
    expect(p('Ad', 'تخفیف ویژه! همین حالا خرید کنید'), isNull);
    expect(p('Saman', '+500,000 مانده 900,000'), isNull);
  });

  test('fingerprint is stable and json round-trips without raw text', () {
    final a = p('Mellat', 'برداشت: 1,000,000')!;
    final b = p('Mellat', 'برداشت: 1,000,000  ')!;
    expect(a.fp, b.fp);
    expect(a.idempotencyKey, matches(RegExp(r'^[A-Za-z0-9_\-]{8,100}$')));
    final j = a.toJson();
    expect(j.values.whereType<String>().any((s) => s.contains('برداشت:')),
        isFalse);
    expect(BankSmsItem.fromJson(j)!.toman, a.toman);
  });

  test('Blu-style: amount then «برداشت» on the same line is confident', () {
    final r = p('blu',
        'بلو\n۱۰۰,۰۰۰ تومان از حساب شما برداشت شد\nمانده: ۲۰,۴۰۰,۰۰۰ تومان\n۱۴۰۵/۰۸/۰۳ ۱۶:۳۵')!;
    expect(r.bank, 'بلو');
    expect(r.toman, 100000);
    expect(r.balanceToman, 20400000);
    expect(r.lowConfidence, isFalse);
  });

  test('single amount besides balance is confident', () {
    final r = p('blu',
        'بلو\nانتقال کارت به کارت\n۵۵,۰۰۰ تومان\nموجودی: ۱,۰۰۰,۰۰۰ تومان')!;
    expect(r.toman, 55000);
    expect(r.lowConfidence, isFalse);
  });

  test('friendly error hides platform stack traces', () {
    expect(
        bankSmsFriendlyError(
            Exception('PlatformException(java.lang.NoSuchMethodError: ...)')),
        isNot(contains('java')));
  });
}

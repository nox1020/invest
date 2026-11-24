// Invented bank SMS (fake amounts/accounts) in the formats of major Iranian
// banks. Shared by the Dart parser tests and the native (Kotlin) inbox-filter
// test, so a format the parser understands is never dropped natively.

class BankSmsSample {
  const BankSmsSample(this.name, this.sender, this.body, this.dir,
      [this.toman, this.balance]);
  final String name;
  final String sender;
  final String body;

  /// 'in', 'out', or null when the SMS must be ignored.
  final String? dir;
  final double? toman;
  final double? balance;
}

const bankSmsSamples = <BankSmsSample>[
  // ── Deposits ────────────────────────────────────────────────────────────
  BankSmsSample(
      'melli deposit, + suffix, space date',
      'BMI',
      'بانک ملی ایران\nواریز: 5,000,000+\nحساب: 0123\nمانده: 12,000,000\n1405/09/03 10:20',
      'in',
      500000,
      1200000),
  BankSmsSample(
      'mellat deposit, dash date',
      '+98700717',
      'بانک ملت\nحساب*1234\nواریز1,500,000\nمانده23,456,789\n0903-12:44',
      'in',
      150000),
  BankSmsSample(
      'pasargad plus-only deposit',
      'bpi',
      'حساب 207.800.123\n+1,000,000\nمانده: 5,000,000\n1405/09/03 10:00',
      'in',
      100000,
      500000),
  BankSmsSample(
      'saman incoming transfer (انتقال then واریز)',
      'Saman',
      'بانک سامان\nانتقال وجه\nواریز:3,000,000\nبه حساب:849-800\nمانده:9,000,000',
      'in',
      300000,
      900000),
  BankSmsSample(
      'tejarat transfer to your account',
      'Tejarat',
      'بانک تجارت\nانتقال به حساب شما\nمبلغ 3,000,000 ریال\nمانده 8,000,000',
      'in',
      300000,
      800000),
  BankSmsSample(
      'blu deposit in toman',
      'blu',
      '۱۰۰,۰۰۰ تومان به حساب شما واریز شد.\nموجودی: ۵۰۰,۰۰۰ تومان',
      'in',
      100000,
      500000),
  BankSmsSample(
      'sepah بستانکار',
      'Sepah',
      'بانک سپه\nبستانکار: 4,000,000\nمانده: 10,000,000',
      'in',
      400000,
      1000000),
  BankSmsSample('melli «مانده حساب» balance', 'BMI',
      'بانک ملی\nواریز 2,000,000\nمانده حساب: 7,000,000', 'in', 200000, 700000),
  BankSmsSample(
      'balance first, amount after',
      'BMI',
      'بانک ملی\nمانده حساب: 7,000,000\n2,000,000 واریز شد',
      'in',
      200000,
      700000),
  BankSmsSample('refund of a purchase', 'BMI',
      'بانک ملی\nواریز بابت برگشت خرید 300,000\nمانده: 1,000,000', 'in', 30000),
  BankSmsSample('no separators, 14.5M rial (not a date)', 'BMI',
      'بانک ملی\nواریز 14500000 ریال\nمانده 20000000', 'in', 1450000),
  BankSmsSample(
      'salary',
      'Melli',
      'بانک ملی\nحقوق واریز شد\nمبلغ: 45,000,000 ریال\nمانده: 46,000,000',
      'in',
      4500000),
  // ── Withdrawals ─────────────────────────────────────────────────────────
  BankSmsSample(
      'mellat withdrawal',
      '+98999000111',
      'بانک ملت\nبرداشت: 1,250,000\nحساب: 123***45\nمانده: 8,400,000\n1405/08/03-14:22',
      'out',
      125000,
      840000),
  BankSmsSample(
      'blu withdrawal from your account',
      'blu',
      '۲۵۰,۰۰۰ تومان از حساب شما برداشت شد.\nموجودی: ۵۰۰,۰۰۰ تومان',
      'out',
      250000,
      500000),
  BankSmsSample('sepah بدهکار', 'Sepah',
      'بانک سپه\nبدهکار: 1,200,000\nمانده: 3,000,000', 'out', 120000, 300000),
  BankSmsSample('balance line first, purchase after', 'BMI',
      'بانک ملی\nمانده حساب: 7,000,000\nخرید 250,000', 'out', 25000, 700000),
  BankSmsSample(
      'pasargad outgoing paya mentions واریز',
      'Pasargad',
      'بانک پاسارگاد\nواریز پایا به حساب IR12\nمبلغ: 9,000,000\nبرداشت از حساب 207\nمانده 1,000,000',
      'out',
      900000),
  BankSmsSample(
      'saman card-to-card out',
      'Saman',
      'بانک سامان\nکارت به کارت\nواریز به کارت 6219****1234\nمبلغ 700,000\nمانده 2,000,000',
      'out',
      70000,
      200000),
  BankSmsSample(
      'tejarat purchase',
      'Tejarat',
      'بانک تجارت\nخرید از فروشگاه\nمبلغ: 3,500,000 ریال\nمانده: 1,000,000\n1405/09/03',
      'out',
      350000,
      100000),
  BankSmsSample('parsian satna', 'Parsian',
      'بانک پارسیان\nساتنا\nمبلغ 50,000,000\nمانده 1,000,000', 'out', 5000000),
  BankSmsSample('saderat minus amount', 'Saderat',
      'صادرات\nخرید\n-750,000\nمانده 1,000,000\n0803-12:00', 'out', 75000),
  // ── Ignored ─────────────────────────────────────────────────────────────
  BankSmsSample('otp', 'Mellat', 'رمز پویا: 123456 مبلغ خرید 1,000,000', null),
  BankSmsSample('ad', 'Ad', 'تخفیف ویژه! همین حالا خرید کنید', null),
  BankSmsSample('failed', 'Mellat', 'بانک ملت\nبرداشت 1,000,000 ناموفق', null),
];

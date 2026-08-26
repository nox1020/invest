class AppSettings {
  AppSettings({
    this.calendar = 'jalali',
    this.currency = 'toman',
    this.theme = 'dark',
    this.livePricesEnabled = true,
    this.usdtApiEnabled = true,
    this.goldApiEnabled = true,
    this.wallexUrl = '',
    this.persianToolboxUrl = '',
    this.usdtTmnRate,
    this.goldTmnPerGram,
  });

  String calendar;
  String currency;
  String theme;
  bool livePricesEnabled;
  bool usdtApiEnabled;
  bool goldApiEnabled;
  String wallexUrl;
  String persianToolboxUrl;
  double? usdtTmnRate;
  double? goldTmnPerGram;

  bool get isDark => theme != 'light';
}

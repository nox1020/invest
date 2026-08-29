/// Application constants and setting keys.
class AppConfig {
  static const appName = 'مدیریت سرمایه و معاملات';
  static const applicationId = 'com.nox1020.invest';

  static const calendarJalali = 'jalali';
  static const calendarGregorian = 'gregorian';

  static const currencyToman = 'toman';
  static const currencyRial = 'rial';
  static const currencyUsd = 'usd';
  static const currencyUsdt = 'usdt';

  static const themeDark = 'dark';
  static const themeLight = 'light';

  static const tradeOpen = 'open';
  static const tradeClosed = 'closed';

  static const settingCalendar = 'calendar';
  static const settingCurrency = 'currency';
  static const settingTheme = 'theme';
  static const settingLivePrices = 'live_prices_enabled';
  static const settingUsdtApi = 'usdt_api_enabled';
  static const settingGoldApi = 'gold_api_enabled';
  static const settingWallexUrl = 'wallex_markets_url';
  static const settingPersianToolboxUrl = 'persiantoolbox_url';
  static const settingUsdtTmn = 'usdt_tmn_rate';
  static const settingGoldTmn = 'gold_tmn_per_gram';

  static const defaultWallexUrl =
      'https://api.wallex.ir/v1/markets';
  static const defaultPersianToolboxUrl =
      'https://api.persiantoolbox.com/v1/metal';

  static const Map<String, String> defaultSettings = {
    settingCalendar: calendarJalali,
    settingCurrency: currencyToman,
    settingTheme: themeDark,
    settingLivePrices: '1',
    settingUsdtApi: '1',
    settingGoldApi: '1',
    settingWallexUrl: defaultWallexUrl,
    settingPersianToolboxUrl: defaultPersianToolboxUrl,
  };
}

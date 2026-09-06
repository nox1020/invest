import 'package:invest/config/app_config.dart';

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

  AppSettings copyWith({
    String? calendar,
    String? currency,
    String? theme,
    bool? livePricesEnabled,
    bool? usdtApiEnabled,
    bool? goldApiEnabled,
    String? wallexUrl,
    String? persianToolboxUrl,
    double? usdtTmnRate,
    double? goldTmnPerGram,
    bool clearUsdtTmnRate = false,
    bool clearGoldTmnPerGram = false,
  }) {
    return AppSettings(
      calendar: calendar ?? this.calendar,
      currency: currency ?? this.currency,
      theme: theme ?? this.theme,
      livePricesEnabled: livePricesEnabled ?? this.livePricesEnabled,
      usdtApiEnabled: usdtApiEnabled ?? this.usdtApiEnabled,
      goldApiEnabled: goldApiEnabled ?? this.goldApiEnabled,
      wallexUrl: wallexUrl ?? this.wallexUrl,
      persianToolboxUrl: persianToolboxUrl ?? this.persianToolboxUrl,
      usdtTmnRate: clearUsdtTmnRate ? null : (usdtTmnRate ?? this.usdtTmnRate),
      goldTmnPerGram:
          clearGoldTmnPerGram ? null : (goldTmnPerGram ?? this.goldTmnPerGram),
    );
  }

  /// Portable JSON used by backups and offline cache.
  Map<String, dynamic> toJson() => {
        'calendar': calendar,
        'currency': currency,
        'theme': theme,
        'live_prices_enabled': livePricesEnabled,
        'usdt_api_enabled': usdtApiEnabled,
        'gold_api_enabled': goldApiEnabled,
        'wallex_url': wallexUrl,
        'persian_toolbox_url': persianToolboxUrl,
        'usdt_tmn_rate': usdtTmnRate,
        'gold_tmn_per_gram': goldTmnPerGram,
      };

  /// Local SQLite / settings-table key map.
  Map<String, String> toStorageMap() => {
        AppConfig.settingCalendar: calendar,
        AppConfig.settingCurrency: currency,
        AppConfig.settingTheme: theme,
        AppConfig.settingLivePrices: livePricesEnabled ? '1' : '0',
        AppConfig.settingUsdtApi: usdtApiEnabled ? '1' : '0',
        AppConfig.settingGoldApi: goldApiEnabled ? '1' : '0',
        AppConfig.settingWallexUrl: wallexUrl,
        AppConfig.settingPersianToolboxUrl: persianToolboxUrl,
        if (usdtTmnRate != null) AppConfig.settingUsdtTmn: '$usdtTmnRate',
        if (goldTmnPerGram != null)
          AppConfig.settingGoldTmn: '$goldTmnPerGram',
      };

  static bool _on(dynamic v, {bool fallback = true}) {
    if (v == null) return fallback;
    if (v is bool) return v;
    if (v is num) return v != 0;
    final t = '$v'.trim().toLowerCase();
    if (t.isEmpty) return fallback;
    return t == '1' || t == 'true' || t == 'yes' || t == 'on';
  }

  static double? _d(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse('$v'.trim().replaceAll(',', ''));
  }

  factory AppSettings.fromJson(Map<String, dynamic> s) {
    return AppSettings(
      calendar: (s['calendar'] as String?) ?? AppConfig.calendarJalali,
      currency: (s['currency'] as String?) ?? AppConfig.currencyToman,
      theme: (s['theme'] as String?) ?? AppConfig.themeDark,
      livePricesEnabled: _on(s['live_prices_enabled']),
      usdtApiEnabled: _on(s['usdt_api_enabled']),
      goldApiEnabled: _on(s['gold_api_enabled']),
      wallexUrl: (s['wallex_url'] as String?) ??
          (s['wallex_markets_url'] as String?) ??
          AppConfig.defaultWallexUrl,
      persianToolboxUrl: (s['persian_toolbox_url'] as String?) ??
          (s['persiantoolbox_url'] as String?) ??
          AppConfig.defaultPersianToolboxUrl,
      usdtTmnRate: _d(s['usdt_tmn_rate']),
      goldTmnPerGram: _d(s['gold_tmn_per_gram']),
    );
  }

  /// Build from the local settings key/value table (and optional extras).
  factory AppSettings.fromStorageMap(Map<String, String> map) {
    return AppSettings.fromJson({
      'calendar': map[AppConfig.settingCalendar],
      'currency': map[AppConfig.settingCurrency],
      'theme': map[AppConfig.settingTheme],
      'live_prices_enabled': map[AppConfig.settingLivePrices],
      'usdt_api_enabled': map[AppConfig.settingUsdtApi],
      'gold_api_enabled': map[AppConfig.settingGoldApi],
      'wallex_url': map[AppConfig.settingWallexUrl],
      'persian_toolbox_url': map[AppConfig.settingPersianToolboxUrl],
      'usdt_tmn_rate': map[AppConfig.settingUsdtTmn],
      'gold_tmn_per_gram': map[AppConfig.settingGoldTmn],
    });
  }
}

import 'dart:ui' show Color;

import 'package:invest/data/invest_api_client.dart' show OfflineCause;

export 'package:invest/data/invest_api_client.dart' show OfflineCause;

/// One connection state for every surface (AppBar subtitle, dashboard tag,
/// value card, banners, pushed pages). Telegram-like wording.
enum AppConnectionStatus {
  connected,
  updating,

  /// Offline and currently probing the server.
  connecting,

  /// No answer at all: no internet, DNS or timeout.
  waitingNetwork,

  /// Server answered with 5xx / HTML / redirect.
  serverDown,

  /// Server rejected the session; cached data is shown read-only.
  reauth,

  /// Local SQLite workspace (no server cache) — writable, never synced.
  localOnly;

  /// Kept for callers that only distinguish online/offline.
  static const offline = waitingNetwork;

  String get label => switch (this) {
        connected => 'متصل',
        updating => 'در حال به‌روزرسانی...',
        connecting => 'در حال اتصال...',
        waitingNetwork => 'آفلاین · در انتظار شبکه',
        serverDown => 'آفلاین · سرور در دسترس نیست',
        reauth => 'نیاز به ورود دوباره',
        localOnly => 'حالت محلی · بدون سرور',
      };

  /// Short chip text (dashboard tag).
  String get short => switch (this) {
        connected || updating => 'همگام',
        connecting => 'در حال اتصال',
        waitingNetwork || serverDown => 'آفلاین',
        reauth => 'ورود لازم',
        localOnly => 'محلی',
      };

  bool get isOnline => this == connected || this == updating;

  /// Offline is a state, not an error: amber everywhere; red only for auth.
  Color get color => switch (this) {
        connected => const Color(0xFF6EE7A8),
        updating || connecting => const Color(0xFFE8F0EC),
        waitingNetwork || serverDown || localOnly => const Color(0xFFE0C46A),
        reauth => const Color(0xFFFF8A80),
      };

  static AppConnectionStatus resolve({
    required bool offline,
    required bool updating,
    bool localOnly = false,
    bool reauth = false,
    OfflineCause? cause,
  }) {
    if (reauth) return AppConnectionStatus.reauth;
    if (localOnly && offline) return AppConnectionStatus.localOnly;
    if (offline) {
      if (updating) return AppConnectionStatus.connecting;
      return cause == OfflineCause.server
          ? AppConnectionStatus.serverDown
          : AppConnectionStatus.waitingNetwork;
    }
    if (updating) return AppConnectionStatus.updating;
    return AppConnectionStatus.connected;
  }
}

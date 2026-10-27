import 'package:flutter/material.dart';
import 'package:invest/domain/services/connection_status.dart';
import 'package:invest/state/app_state.dart';
import 'package:invest/ui/theme/app_theme.dart';
import 'package:invest/ui/widgets/dashboard_kit.dart' show hhmm;
import 'package:provider/provider.dart';

String _syncTail(DateTime? at) =>
    at == null ? '' : ' آخرین همگام‌سازی ${hhmm(at)}';

/// Why a write is refused right now — one wording for every snackbar.
String readOnlyMessage(AppState state) {
  if (state.reauthRequired) {
    return 'نشست سرور منقضی شده است. برای ثبت تغییر دوباره وارد شوید.';
  }
  return switch (state.connectionStatus) {
    AppConnectionStatus.serverDown =>
      'سرور در دسترس نیست؛ تغییرها روی گوشی ذخیره و بعد از اتصال ارسال می‌شوند.',
    _ =>
      'آفلاین هستید؛ تغییرها روی گوشی ذخیره و بعد از اتصال خودکار ارسال می‌شوند.',
  };
}

void showReadOnlySnack(BuildContext context) {
  final state = context.read<AppState>();
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(readOnlyMessage(state))));
}

/// Home-shell notice under the AppBar while offline: reason, last sync and
/// a retry. Auth expiry has its own banner; nothing shows when online.
class OfflineReadOnlyNotice extends StatelessWidget {
  const OfflineReadOnlyNotice({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final st = state.connectionStatus;
    if (st.isOnline || st == AppConnectionStatus.reauth) {
      return const SizedBox.shrink();
    }
    final sync = _syncTail(state.lastSyncedAt);
    final text = switch (st) {
      AppConnectionStatus.localOnly =>
        'حالت محلی: داده‌ها فقط روی همین گوشی است و با سرور همگام نمی‌شود.',
      AppConnectionStatus.serverDown =>
        'سرور پاسخ نمی‌دهد. می‌توانید ثبت و ویرایش کنید؛ تغییرها در صف می‌مانند و بعد از اتصال ارسال می‌شوند.$sync',
      AppConnectionStatus.connecting =>
        'در حال اتصال به سرور… داده‌های ذخیره‌شده نمایش داده می‌شود.$sync',
      _ =>
        'اینترنت در دسترس نیست. می‌توانید ثبت و ویرایش کنید؛ با برگشتن اتصال همه‌چیز خودکار ارسال می‌شود.$sync',
    };
    final busy = state.refreshing;
    return Container(
      key: const ValueKey('offline-notice'),
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: st.color.withValues(alpha: 0.45)),
      ),
      child: Row(children: [
        Icon(
            st == AppConnectionStatus.localOnly
                ? Icons.phone_android_rounded
                : Icons.cloud_off_rounded,
            size: 18,
            color: st.color),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text,
              textAlign: TextAlign.right,
              style: const TextStyle(
                  color: AppTheme.text, fontSize: 12, height: 1.45)),
        ),
        const SizedBox(width: 4),
        TextButton(
          key: const ValueKey('offline-retry'),
          style: TextButton.styleFrom(foregroundColor: AppTheme.positive),
          onPressed: busy ? null : () => state.tryGoOnline(),
          child: Text(busy
              ? 'در حال اتصال…'
              : st == AppConnectionStatus.localOnly
                  ? 'اتصال به سرور'
                  : 'تلاش دوباره'),
        ),
      ]),
    );
  }
}

/// Slim AppBar bottom for pushed pages (چک‌ها، ملک و دفتر، پروژه‌ها، …) so
/// they show the same offline state as the home shell. Null when online.
PreferredSizeWidget? connectionStripFor(BuildContext context,
    {PreferredSizeWidget? below, bool queuesWrites = false}) {
  final AppState state;
  try {
    state = Provider.of<AppState>(context);
  } on ProviderNotFoundException {
    return below; // standalone pages in tests / previews
  }
  final st = state.connectionStatus;
  if (st.isOnline) return below;
  final strip = _strip(state, st, queuesWrites);
  if (below == null) return strip;
  return PreferredSize(
    preferredSize: Size.fromHeight(26 + below.preferredSize.height),
    child: Column(mainAxisSize: MainAxisSize.min, children: [strip, below]),
  );
}

PreferredSizeWidget _strip(
    AppState state, AppConnectionStatus st, bool queuesWrites) {
  return PreferredSize(
    preferredSize: const Size.fromHeight(26),
    child: Container(
      key: const ValueKey('conn-strip'),
      height: 26,
      color: st.color.withValues(alpha: 0.12),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(color: st.color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            (queuesWrites || state.readOnlyOffline) &&
                    st != AppConnectionStatus.localOnly &&
                    st != AppConnectionStatus.reauth
                ? '${st.label} · تغییرات در صف می‌ماند'
                : st.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.right,
            style: TextStyle(color: st.color, fontSize: 11.5),
          ),
        ),
      ]),
    ),
  );
}

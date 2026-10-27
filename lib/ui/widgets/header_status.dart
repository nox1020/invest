import 'package:flutter/material.dart';
import 'package:invest/data/biz_store.dart';
import 'package:invest/data/projects_store.dart';
import 'package:invest/data/pwo_store.dart';
import 'package:invest/data/write_queue.dart';
import 'package:invest/domain/services/connection_status.dart';
import 'package:invest/state/app_state.dart';
import 'package:invest/ui/pages/login_page.dart';
import 'package:invest/ui/theme/app_theme.dart';
import 'package:invest/ui/widgets/dashboard_kit.dart' show fa, hhmm;
import 'package:provider/provider.dart';

/// A page-level data source whose sync state joins the header line
/// (ملک و دفتر، پروژه‌ها، PWO).
class StoreStatusSource {
  const StoreStatusSource({
    required this.listenable,
    required this.syncing,
    required this.error,
    required this.retry,
  });
  final Listenable listenable;
  final bool Function() syncing;

  /// A real refresh failure while the app itself is online. The
  /// "showing cache while offline" note is not an error.
  final bool Function() error;
  final Future<void> Function() retry;

  static StoreStatusSource biz(BizStore s) => StoreStatusSource(
      listenable: s,
      syncing: () => s.syncing,
      error: () => s.lastError != null && s.lastError != offlineQueueNote,
      retry: s.refresh);
  static StoreStatusSource projects(ProjectsStore s) => StoreStatusSource(
      listenable: s,
      syncing: () => s.syncing,
      error: () => s.lastError != null && s.lastError != offlineQueueNote,
      retry: s.refresh);
  static StoreStatusSource pwo(PwoStore s) => StoreStatusSource(
      listenable: s,
      syncing: () => s.syncing,
      error: () => s.lastError != null && s.lastError != offlineQueueNote,
      retry: s.refresh);
}

enum HeaderTone { ok, busy, warn, bad }

/// One short line under the page title. Every connection / sync notice of
/// the app is summarised here; details live in [showStatusSheet].
class HeaderStatus {
  const HeaderStatus(this.text, this.icon, this.tone);
  final String text;
  final IconData icon;
  final HeaderTone tone;

  bool get ok => tone == HeaderTone.ok;
  bool get busy => tone == HeaderTone.busy;

  Color get color => switch (tone) {
        HeaderTone.ok => const Color(0xFF6EE7A8),
        HeaderTone.busy => const Color(0xFFE8F0EC),
        HeaderTone.warn => const Color(0xFFE0C46A),
        HeaderTone.bad => const Color(0xFFFF8A80),
      };

  static HeaderStatus of({
    required AppConnectionStatus conn,
    bool error = false,
    bool syncing = false,
    int pending = 0,
  }) {
    // Exactly three labels: «متصل» · «آفلاین» · «در حال بروزرسانی».
    const off = 'آفلاین', busy = 'در حال بروزرسانی', on = 'متصل';
    final base = switch (conn) {
      AppConnectionStatus.reauth =>
        const HeaderStatus(off, Icons.lock_outline_rounded, HeaderTone.bad),
      AppConnectionStatus.connecting =>
        const HeaderStatus(busy, Icons.sync_rounded, HeaderTone.busy),
      AppConnectionStatus.waitingNetwork ||
      AppConnectionStatus.serverDown =>
        const HeaderStatus(off, Icons.cloud_off_rounded, HeaderTone.warn),
      AppConnectionStatus.localOnly =>
        const HeaderStatus(off, Icons.phone_android_rounded, HeaderTone.warn),
      _ when error =>
        const HeaderStatus(off, Icons.cloud_off_rounded, HeaderTone.warn),
      AppConnectionStatus.updating =>
        const HeaderStatus(busy, Icons.sync_rounded, HeaderTone.busy),
      _ when syncing =>
        const HeaderStatus(busy, Icons.sync_rounded, HeaderTone.busy),
      _ => const HeaderStatus(on, Icons.circle, HeaderTone.ok),
    };
    // Queued writes add no text (one-word header); the line stays visible
    // on pushed pages and the sheet lists them.
    if (pending <= 0) return base;
    // Pending count joins the one-line summary: «آفلاین (۳ در صف)».
    final text = '${base.text} (${fa('$pending')} در صف)';
    if (base.tone != HeaderTone.ok) return HeaderStatus(text, base.icon, base.tone);
    return HeaderStatus(text, Icons.cloud_upload_outlined, HeaderTone.warn);
  }
}

List<WriteQueue> get _queues => [
      PwoStore.instance.queue,
      BizStore.instance.queue,
      ProjectsStore.instance.queue,
    ];

/// Two-line AppBar title: page name + the one-line status. Tapping the
/// status opens the details sheet. [alwaysShow] keeps «متصل» visible (home
/// shell); pushed pages show the line only when something needs attention.
class HeaderStatusTitle extends StatelessWidget {
  const HeaderStatusTitle({
    super.key,
    required this.title,
    this.source,
    this.alwaysShow = false,
    this.extraBusy = false,
    this.extraError = false,
  });

  final String title;
  final StoreStatusSource? source;
  final bool alwaysShow;

  /// Page-local loading (e.g. the market index tab).
  final bool extraBusy;

  /// Page-local refresh failure (e.g. market index feed).
  final bool extraError;

  @override
  Widget build(BuildContext context) {
    AppState? state;
    try {
      state = Provider.of<AppState>(context);
    } on ProviderNotFoundException {
      state = null;
    }
    final titleText = Text(title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
            color: Colors.white,
            fontSize: 17,
            fontWeight: FontWeight.w600,
            height: 1.15));
    if (state == null) return titleText;
    final s = state;
    return ListenableBuilder(
      listenable: Listenable.merge(
          [..._queues, s.coreOutbox, if (source != null) source!.listenable]),
      builder: (context, _) {
        var conn = s.connectionStatus;
        if (conn == AppConnectionStatus.connected && extraBusy) {
          conn = AppConnectionStatus.updating;
        }
        final st = HeaderStatus.of(
          conn: conn,
          error: extraError ||
              (s.error ?? '').trim().isNotEmpty ||
              s.checksAwaitingServer ||
              (source?.error() ?? false),
          syncing: source?.syncing() ?? false,
          pending: s.pendingWrites,
        );
        final show = alwaysShow || !st.ok;
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            titleText,
            if (show) ...[
              const SizedBox(height: 2),
              Semantics(
                button: true,
                label: 'وضعیت اتصال: ${st.text}',
                excludeSemantics: true,
                child: InkWell(
                  key: const ValueKey('header-status'),
                  borderRadius: BorderRadius.circular(6),
                  onTap: () => showStatusSheet(context, source: source),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      if (st.busy)
                        SizedBox(
                            width: 11,
                            height: 11,
                            child: CircularProgressIndicator(
                                strokeWidth: 1.8, color: st.color))
                      else
                        Icon(st.icon, size: st.ok ? 7 : 12, color: st.color),
                      const SizedBox(width: 5),
                      Flexible(
                        child: Text(st.text,
                            key: const ValueKey('header-status-text'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: st.color,
                                fontSize: 12,
                                height: 1.1,
                                fontWeight: FontWeight.w500)),
                      ),
                      if (!st.ok) ...[
                        const SizedBox(width: 2),
                        Icon(Icons.expand_more_rounded,
                            size: 14, color: st.color),
                      ],
                    ]),
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

String _detailFor(AppConnectionStatus c, bool error) => switch (c) {
      AppConnectionStatus.reauth =>
        'نشست شما در سرور منقضی شده است. داده‌های ذخیره‌شده سر جایش است؛ برای ثبت تغییر دوباره وارد شوید.',
      AppConnectionStatus.connecting =>
        'در حال تلاش برای اتصال به سرور. تا آن موقع داده‌های ذخیره‌شده نمایش داده می‌شود.',
      AppConnectionStatus.waitingNetwork =>
        'گوشی به سرور نمی‌رسد (اینترنت را بررسی کنید؛ سرور فقط از داخل ایران در دسترس است، فیلترشکن را خاموش کنید). ثبت و ویرایش ممکن است؛ تغییرها در صف می‌مانند و با برگشتن اتصال خودکار ارسال می‌شوند.',
      AppConnectionStatus.serverDown =>
        'سرور موقتاً پاسخ درست نمی‌دهد. تغییرها روی گوشی در صف می‌مانند و خودکار دوباره ارسال می‌شوند.',
      AppConnectionStatus.localOnly =>
        'داده‌ها فقط روی همین گوشی است و با سرور همگام نمی‌شود.',
      _ when error =>
        'بخشی از داده‌ها به‌روز نشد. آخرین داده‌های موجود نمایش داده می‌شود.',
      _ => 'همه‌چیز با سرور همگام است.',
    };

/// Details + actions for the header status (retry, re-login, send queue).
Future<void> showStatusSheet(BuildContext context,
    {StoreStatusSource? source}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    backgroundColor: AppTheme.card,
    builder: (_) => ChangeNotifierProvider.value(
      value: context.read<AppState>(),
      child: _StatusSheet(source: source),
    ),
  );
}

class _StatusSheet extends StatelessWidget {
  const _StatusSheet({this.source});
  final StoreStatusSource? source;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    return ListenableBuilder(
      listenable: Listenable.merge(
          [..._queues, s.coreOutbox, if (source != null) source!.listenable]),
      builder: (context, _) {
        final conn = s.connectionStatus;
        final error =
            (s.error ?? '').trim().isNotEmpty || (source?.error() ?? false);
        final st = HeaderStatus.of(
            conn: conn,
            error: error || s.checksAwaitingServer,
            syncing: source?.syncing() ?? false,
            pending: s.pendingWrites);
        final items = <_Pending>[
          for (final o in s.coreOutbox.ops)
            _Pending(o.key, o.label, o.error,
                () => s.coreOutbox.discard(o.key).then((_) => s.notifyListeners()),
                () => s.coreOutbox.retry(o.key)),
          for (final q in _queues)
            for (final w in q.items)
              _Pending(w.key, w.label, w.error, () => q.discard(w.key), () => q.retry(w.key)),
          if (s.checksAwaitingServer || (s.pendingWrites > 0 && s.dirtyCheckIds.isNotEmpty))
            _Pending('checks', 'دفتر چک‌ها (${fa('${s.dirtyCheckIds.length}')} چک ویرایش‌شده)', null, null, null),
        ];
        final busy = s.refreshing || (source?.syncing() ?? false);
        Future<void> retry() async {
          for (final i in items) {
            await i.retry?.call(); // refused items are tried once more
          }
          if (s.offline) {
            await s.tryGoOnline();
          } else {
            await s.refreshAll(includeQuotes: true);
          }
          await source?.retry();
          await s.syncNow();
        }

        return Directionality(
          textDirection: TextDirection.rtl,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: Column(
                key: const ValueKey('status-sheet'),
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(children: [
                    Icon(st.icon, color: st.color, size: st.ok ? 10 : 20),
                    const SizedBox(width: 8),
                    Text(st.text,
                        style: TextStyle(
                            color: st.color,
                            fontSize: 16,
                            fontWeight: FontWeight.w800)),
                  ]),
                  const SizedBox(height: 8),
                  Text(_detailFor(conn, error),
                      style: const TextStyle(
                          color: AppTheme.text, fontSize: 13, height: 1.5)),
                  if (s.checksAwaitingServer)
                    const Padding(
                      padding: EdgeInsets.only(top: 6),
                      child: Text(
                          'دفتر چک‌ها روی گوشی ذخیره است و با اتصال بعدی به سرور فرستاده می‌شود.',
                          style: TextStyle(
                              color: AppTheme.muted,
                              fontSize: 12,
                              height: 1.5)),
                    ),
                  if (s.lastSyncedAt != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text('آخرین همگام‌سازی ${hhmm(s.lastSyncedAt!)}',
                          style: const TextStyle(
                              color: AppTheme.muted, fontSize: 12)),
                    ),
                  if (items.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    Text('${fa('${items.length}')} تغییر در صف ارسال',
                        style: const TextStyle(
                            color: AppTheme.title,
                            fontWeight: FontWeight.w700,
                            fontSize: 13)),
                    for (final w in items.take(8))
                      Row(children: [
                        Expanded(
                          child: Text(
                              w.error == null
                                  ? w.label
                                  : '${w.label} · سرور نپذیرفت: ${w.error}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 12,
                                  color: w.error == null
                                      ? AppTheme.text
                                      : const Color(0xFFFF8A80))),
                        ),
                        if (w.discard != null)
                          IconButton(
                            key: ValueKey('sheet-discard-${w.key}'),
                            tooltip: 'دور انداختن',
                            visualDensity: VisualDensity.compact,
                            icon: const Icon(Icons.close_rounded, size: 18),
                            onPressed: () => _confirmDiscard(context, w),
                          ),
                      ]),
                    if (items.length > 8)
                      Text('و ${fa('${items.length - 8}')} مورد دیگر',
                          style: const TextStyle(
                              color: AppTheme.muted, fontSize: 12)),
                  ],
                  const SizedBox(height: 16),
                  if (conn == AppConnectionStatus.reauth)
                    FilledButton(
                      key: const ValueKey('sheet-login'),
                      onPressed: () {
                        Navigator.of(context).pop();
                        Navigator.of(context).push(MaterialPageRoute<void>(
                            builder: (_) => const LoginPage()));
                      },
                      child: const Text('ورود دوباره'),
                    )
                  else
                    FilledButton(
                      key: const ValueKey('sheet-retry'),
                      onPressed: busy ? null : retry,
                      child: Text(busy
                          ? 'در حال تلاش…'
                          : items.isNotEmpty
                              ? 'تلاش دوباره و ارسال صف'
                              : conn == AppConnectionStatus.localOnly
                                  ? 'اتصال به سرور'
                                  : 'تلاش دوباره'),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}


class _Pending {
  const _Pending(this.key, this.label, this.error, this.discard, this.retry);
  final String key;
  final String label;
  final String? error;
  final Future<void> Function()? discard;
  final Future<void> Function()? retry;
}

/// Discarding loses an unsent edit, so it is confirmed first.
Future<void> _confirmDiscard(BuildContext context, _Pending w) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title: const Text('دور انداختن تغییر؟'),
        content: Text('«${w.label}» هنوز به سرور نرسیده و با دور انداختن از گوشی هم پاک می‌شود.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('انصراف')),
          TextButton(
              key: const ValueKey('discard-confirm'),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('دور انداختن', style: TextStyle(color: Color(0xFFFF8A80)))),
        ],
      ),
    ),
  );
  if (ok == true) await w.discard?.call();
}

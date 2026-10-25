import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:invest/data/bank_sms_store.dart';
import 'package:invest/ui/theme/app_theme.dart';
import 'package:invest/ui/widgets/dashboard_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Bump when a release adds a permission, so the screen shows once more.
const kPermOnboardingVersion = 1;
const _kSeen = 'perm_onboarding_seen_v';

/// First launch (and after an update that adds permissions): open the
/// permissions screen once. Never blocks the app; not shown off-Android.
Future<void> maybeShowPermissionsOnboarding(BuildContext context) async {
  try {
    final p = await SharedPreferences.getInstance();
    if ((p.getInt(_kSeen) ?? 0) >= kPermOnboardingVersion) return;
    // No timer here (cheap probe): absent native side → not shown.
    try {
      await BankSmsStore.channel.invokeMethod<Object?>('status');
    } on MissingPluginException {
      return;
    }
    if (!context.mounted) return;
    await openPermissionsPage(context);
  } catch (_) {}
}

Future<void> openPermissionsPage(BuildContext context) =>
    Navigator.of(context).push(MaterialPageRoute<void>(
        fullscreenDialog: true, builder: (_) => const PermissionsPage()));

Future<void> markPermissionsSeen() async {
  try {
    final p = await SharedPreferences.getInstance();
    await p.setInt(_kSeen, kPermOnboardingVersion);
  } catch (_) {}
}

class PermissionsPage extends StatefulWidget {
  const PermissionsPage({super.key});

  @override
  State<PermissionsPage> createState() => _PermissionsPageState();
}

class _PermissionsPageState extends State<PermissionsPage>
    with WidgetsBindingObserver {
  final store = BankSmsStore.instance;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    store.refreshCaps();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed) _afterChange();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _afterChange() async {
    final c = await store.refreshCaps();
    // SMS allowed here → bank-SMS auto-record on (persisted).
    if (c.supported && c.receive && !store.enabled) {
      await store.setEnabled(true);
    }
  }

  Future<void> _allowAll() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      var c = await store.requestPermissions(); // SMS + notifications
      if (!c.battery) {
        await store.requestBattery();
      }
      c = await store.refreshCaps();
      await _afterChange();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _done() async {
    await markPermissionsSeen();
    if (mounted) Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: ListenableBuilder(
        listenable: store,
        builder: (context, _) {
          final c = store.caps;
          final checked = store.capsChecked;
          final smsOk = c.receive && c.read;
          final smsDenied = checked && c.supported && !c.unknown && !c.receive;
          final fsNeeded = c.sdk >= 34;
          return PopScope(
            onPopInvokedWithResult: (_, __) => markPermissionsSeen(),
            child: Scaffold(
              appBar: AppBar(
                title: const Text('اجازه‌های برنامه'),
                actions: [
                  TextButton(
                    key: const ValueKey('perm-later'),
                    style: TextButton.styleFrom(foregroundColor: Colors.white),
                    onPressed: _done,
                    child: const Text('بعداً'),
                  ),
                ],
              ),
              body: ListView(
                key: const ValueKey('perm-page'),
                padding: EdgeInsets.fromLTRB(
                    16, 12, 16, 24 + MediaQuery.viewPaddingOf(context).bottom),
                children: [
                  Text(
                      'برای کار کامل برنامه این اجازه‌ها لازم است. هر کدام را ندهید، برنامه باز هم کار می‌کند.',
                      style: mutedStyle(13)),
                  const SizedBox(height: 12),
                  _Row(
                    k: 'perm-sms',
                    icon: Icons.sms_rounded,
                    title: 'پیامک',
                    sub:
                        'خواندن پیامک برداشت بانک برای ثبت سریع (فقط روی گوشی).',
                    state: !checked ? null : smsOk,
                  ),
                  _Row(
                    k: 'perm-notif',
                    icon: Icons.notifications_rounded,
                    title: 'اعلان‌ها',
                    sub: 'هشدار قیمت و سود، و پنجرهٔ ثبت برداشت از پیامک.',
                    state: !checked ? null : c.notify,
                  ),
                  _Row(
                    k: 'perm-battery',
                    icon: Icons.battery_charging_full_rounded,
                    title: 'بهینه‌سازی باتری',
                    sub:
                        'تا اندروید پیامک و هشدارها را در پس‌زمینه متوقف نکند.',
                    state: !checked ? null : c.battery,
                    action: c.battery ? null : 'درخواست',
                    onAction: () => store.requestBattery(),
                  ),
                  if (fsNeeded)
                    _Row(
                      k: 'perm-fullscreen',
                      icon: Icons.open_in_full_rounded,
                      title: 'پنجرهٔ تمام‌صفحه',
                      sub: 'نمایش فوری پنجرهٔ ثبت برداشت روی صفحهٔ قفل.',
                      state: !checked ? null : c.fullScreen,
                      action: c.fullScreen ? null : 'تنظیمات',
                      onAction: store.openFullScreenSettings,
                    ),
                  _Row(
                    k: 'perm-autostart',
                    icon: Icons.restart_alt_rounded,
                    title: 'اجرای خودکار (سامسونگ، شیائومی و…)',
                    sub: 'در بعضی گوشی‌ها اجرای پس‌زمینه را دستی روشن کنید.',
                    state: null,
                    unknownText: 'دستی',
                    action: 'باز کردن',
                    onAction: store.openAutostart,
                  ),
                  if (smsDenied)
                    Container(
                      key: const ValueKey('perm-restricted'),
                      margin: const EdgeInsets.only(top: 8),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.orange.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text(
                            'اگر اندروید اجازهٔ پیامک را نداد (اندروید ۱۳ به بعد برای برنامه‌های نصب‌شده با APK): «تنظیمات برنامه» › منوی سه‌نقطه › «اجازه دادن به تنظیمات محدودشده» › «مجوزها» › «پیامک» › «اجازه دادن».',
                            style: TextStyle(fontSize: 12, height: 1.6),
                          ),
                          Align(
                            alignment: AlignmentDirectional.centerEnd,
                            child: OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.white),
                              onPressed: store.openAppSettings,
                              child: const Text('تنظیمات برنامه'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    key: const ValueKey('perm-allow'),
                    onPressed: _busy ? null : _allowAll,
                    icon: _busy
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.verified_user_rounded),
                    label: const Text('اجازه بده'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton(
                    key: const ValueKey('perm-done'),
                    style:
                        OutlinedButton.styleFrom(foregroundColor: Colors.white),
                    onPressed: _done,
                    child: const Text('ادامه'),
                  ),
                  const SizedBox(height: 8),
                  Text('بعداً از تنظیمات › اجازه‌های برنامه هم در دسترس است.',
                      textAlign: TextAlign.center, style: mutedStyle(11)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.k,
    required this.icon,
    required this.title,
    required this.sub,
    required this.state,
    this.unknownText,
    this.action,
    this.onAction,
  });
  final String k;
  final IconData icon;
  final String title, sub;

  /// true granted, false missing, null checking / not checkable.
  final bool? state;
  final String? unknownText;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final color = state == null
        ? AppTheme.muted
        : state!
            ? AppTheme.positive
            : AppTheme.negative;
    final label = state == null
        ? (unknownText ?? 'در حال بررسی')
        : state!
            ? 'داده شده'
            : 'داده نشده';
    return Card(
      key: ValueKey(k),
      color: AppTheme.card,
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(children: [
          Icon(icon, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(sub, style: mutedStyle(12)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(label,
                  key: ValueKey('$k-state'),
                  style: TextStyle(fontSize: 12, color: color)),
              if (action != null)
                OutlinedButton(
                  key: ValueKey('$k-action'),
                  style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      visualDensity: VisualDensity.compact),
                  onPressed: onAction,
                  child: Text(action!),
                ),
            ],
          ),
        ]),
      ),
    );
  }
}

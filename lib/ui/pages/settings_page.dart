import 'package:flutter/material.dart';
import 'package:invest/config/app_config.dart';
import 'package:invest/domain/models/app_settings.dart';
import 'package:invest/domain/services/notification_service.dart';
import 'package:invest/ui/layout/page_padding.dart';
import 'package:invest/ui/pages/app_lock_page.dart';
import 'package:invest/ui/pages/price_alerts_page.dart';
import 'package:invest/ui/theme/app_theme.dart';
import 'package:invest/ui/widgets/backup_actions.dart';
import 'package:invest/ui/widgets/settings_ui.dart';
import 'package:invest/state/app_state.dart';
import 'package:provider/provider.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AppState>().refreshBiometricCapability();
    });
  }

  AppSettings _clone(AppSettings s) => s.copyWith();

  Future<void> _persist(
    AppState state,
    void Function(AppSettings s) mutate,
  ) async {
    if (_busy || state.readOnlyOffline) {
      if (state.readOnlyOffline && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('در حالت آفلاین ذخیره ممکن نیست'),
          ),
        );
      }
      return;
    }
    final next = _clone(state.settings);
    mutate(next);
    setState(() => _busy = true);
    try {
      await state.saveSettings(next);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('ذخیره تنظیمات ناموفق: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _removeAppLock(AppState state) async {
    final messenger = ScaffoldMessenger.of(context);
    final pwdCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف رمز ورود'),
        content: TextField(
          controller: pwdCtrl,
          obscureText: true,
          decoration: const InputDecoration(labelText: 'رمز فعلی'),
          textAlign: TextAlign.center,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('انصراف'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) {
      pwdCtrl.dispose();
      return;
    }
    final valid = await state.unlockApp(pwdCtrl.text);
    pwdCtrl.dispose();
    if (!valid) {
      if (mounted) {
        messenger.showSnackBar(
          const SnackBar(content: Text('رمز فعلی نادرست است.')),
        );
      }
      return;
    }
    await state.removeAppLock();
    if (mounted) {
      messenger.showSnackBar(
        const SnackBar(content: Text('رمز ورود حذف شد')),
      );
    }
  }

  String _calendarLabel(String v) =>
      v == AppConfig.calendarGregorian ? 'میلادی' : 'شمسی';

  String _currencyLabel(String v) => switch (v) {
        AppConfig.currencyRial => 'ریال',
        AppConfig.currencyUsd => 'دلار',
        AppConfig.currencyUsdt => 'تتر',
        _ => 'تومان',
      };

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final s = state.settings;
    final isDark = s.isDark;
    final canEdit = !_busy && !state.readOnlyOffline;

    return ColoredBox(
      color: tgSettingsPageBg(context),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: shellPagePadding(),
        children: [
          TgSettingsSection(
            title: 'امنیت',
            children: [
              TgSettingsTile(
                icon: Icons.lock_rounded,
                iconColor: const Color(0xFF34AADF),
                title: state.appLockEnabled ? 'رمز ورود' : 'تنظیم رمز ورود',
                value: state.appLockEnabled ? 'فعال' : 'خاموش',
                onTap: () async {
                  final saved = await showAppLockSetDialog(
                    context,
                    hasLock: state.appLockEnabled,
                  );
                  if (saved && context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('رمز ورود ذخیره شد')),
                    );
                  }
                },
                showDivider: state.appLockEnabled ||
                    state.biometricDeviceSupported,
              ),
              if (state.appLockEnabled)
                TgSettingsTile(
                  icon: Icons.lock_open_rounded,
                  iconColor: const Color(0xFFFF3B30),
                  title: 'حذف رمز ورود',
                  destructive: true,
                  onTap: () => _removeAppLock(state),
                  showDivider: state.biometricDeviceSupported,
                ),
              if (state.biometricDeviceSupported)
                TgSettingsSwitchTile(
                  icon: Icons.fingerprint_rounded,
                  iconColor: const Color(0xFF5856D6),
                  title: 'باز کردن با ${state.biometricLabel}',
                  subtitle: !state.appLockEnabled
                      ? 'ابتدا رمز ورود را تنظیم کنید'
                      : !state.biometricAvailable
                          ? 'اثر انگشت یا چهره را در گوشی ثبت کنید'
                          : null,
                  value: state.biometricUnlockEnabled,
                  onChanged: state.appLockEnabled &&
                          state.biometricAvailable &&
                          canEdit
                      ? (value) async {
                          final err =
                              await state.setBiometricUnlockEnabled(value);
                          if (!mounted) return;
                          if (err != null) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(err)),
                            );
                          }
                        }
                      : null,
                  showDivider: false,
                ),
            ],
          ),
          if (state.useRemote)
            TgSettingsSection(
              title: 'حساب',
              children: [
                TgSettingsTile(
                  icon: Icons.phone_iphone_rounded,
                  iconColor: const Color(0xFF30D158),
                  title: 'شماره موبایل',
                  value: state.userPhone ?? '—',
                  showDivider: true,
                ),
                TgSettingsTile(
                  icon: Icons.logout_rounded,
                  iconColor: const Color(0xFFFF3B30),
                  title: 'خروج از حساب',
                  destructive: true,
                  onTap: () => state.logout(),
                  showDivider: false,
                ),
              ],
            ),
          TgSettingsSection(
            title: 'پشتیبان‌گیری',
            children: [
              TgSettingsTile(
                icon: Icons.ios_share_rounded,
                iconColor: const Color(0xFF64D2FF),
                title: 'صدور پشتیبان',
                subtitle: 'همه داده‌ها + تنظیمات (رمزگذاری‌شده)',
                onTap: state.authenticated
                    ? () => exportAppBackup(context)
                    : null,
              ),
              TgSettingsTile(
                icon: Icons.download_rounded,
                iconColor: const Color(0xFF64D2FF),
                title: 'ورود پشتیبان',
                subtitle: 'جایگزینی کامل شامل تنظیمات',
                onTap: state.authenticated
                    ? () => importAppBackup(context)
                    : null,
                showDivider: false,
              ),
            ],
          ),
          TgSettingsSection(
            title: 'ظاهر و نمایش',
            children: [
              TgSettingsSwitchTile(
                icon: Icons.dark_mode_rounded,
                iconColor: const Color(0xFF8E8E93),
                title: 'تم تاریک',
                value: isDark,
                onChanged: canEdit
                    ? (v) => _persist(
                          state,
                          (d) => d.theme =
                              v ? AppConfig.themeDark : AppConfig.themeLight,
                        )
                    : null,
              ),
              TgSettingsTile(
                icon: Icons.calendar_month_rounded,
                iconColor: const Color(0xFFFF9500),
                title: 'تقویم',
                value: _calendarLabel(s.calendar),
                onTap: !canEdit
                    ? null
                    : () async {
                        final picked = await showTgChoiceSheet<String>(
                          context: context,
                          title: 'تقویم',
                          selected: s.calendar,
                          options: const [
                            (
                              value: AppConfig.calendarJalali,
                              label: 'شمسی',
                            ),
                            (
                              value: AppConfig.calendarGregorian,
                              label: 'میلادی',
                            ),
                          ],
                        );
                        if (picked == null || !mounted) return;
                        await _persist(state, (d) => d.calendar = picked);
                      },
              ),
              TgSettingsTile(
                icon: Icons.payments_rounded,
                iconColor: const Color(0xFF34C759),
                title: 'ارز نمایش',
                value: _currencyLabel(s.currency),
                onTap: !canEdit
                    ? null
                    : () async {
                        final picked = await showTgChoiceSheet<String>(
                          context: context,
                          title: 'ارز نمایش',
                          selected: s.currency,
                          options: const [
                            (
                              value: AppConfig.currencyToman,
                              label: 'تومان',
                            ),
                            (
                              value: AppConfig.currencyRial,
                              label: 'ریال',
                            ),
                            (
                              value: AppConfig.currencyUsd,
                              label: 'دلار',
                            ),
                            (
                              value: AppConfig.currencyUsdt,
                              label: 'تتر',
                            ),
                          ],
                        );
                        if (picked == null || !mounted) return;
                        await _persist(state, (d) => d.currency = picked);
                      },
                showDivider: false,
              ),
            ],
          ),
          TgSettingsSection(
            title: 'اعلان‌ها',
            children: [
              TgSettingsSwitchTile(
                icon: Icons.notifications_rounded,
                iconColor: const Color(0xFFFF3B30),
                title: 'اعلان‌های دستگاه',
                subtitle: s.notificationsEnabled
                    ? 'نوتیفیکیشن‌های محلی فعال است'
                    : 'همه اعلان‌ها خاموش',
                value: s.notificationsEnabled,
                onChanged: !canEdit
                    ? null
                    : (v) async {
                        if (v) {
                          final ok = await NotificationService.instance
                              .requestPermission();
                          if (!ok) {
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'اجازه اعلان در تنظیمات سیستم داده نشد',
                                ),
                              ),
                            );
                            return;
                          }
                        }
                        await _persist(
                          state,
                          (d) => d.notificationsEnabled = v,
                        );
                      },
              ),
              TgSettingsSwitchTile(
                icon: Icons.swap_horiz_rounded,
                iconColor: const Color(0xFF007AFF),
                title: 'معاملات',
                subtitle: s.armedProfitAlertCount > 0
                    ? '${s.armedProfitAlertCount} آستانه سود · خرید و فروش'
                    : 'خرید، فروش و آستانه سود',
                value: s.notifyTrades,
                onChanged: canEdit && s.notificationsEnabled
                    ? (v) => _persist(state, (d) => d.notifyTrades = v)
                    : null,
              ),
              TgSettingsSwitchTile(
                icon: Icons.payments_outlined,
                iconColor: const Color(0xFF34C759),
                title: 'برداشت‌ها',
                subtitle: 'ثبت برداشت جدید',
                value: s.notifyWithdrawals,
                onChanged: canEdit && s.notificationsEnabled
                    ? (v) => _persist(state, (d) => d.notifyWithdrawals = v)
                    : null,
              ),
              TgSettingsSwitchTile(
                icon: Icons.trending_up_rounded,
                iconColor: const Color(0xFFFF9500),
                title: 'هشدار قیمت',
                subtitle: s.armedPriceAlertCount > 0
                    ? '${s.armedPriceAlertCount} ارز با آستانه'
                    : 'سقف و کف قیمت هر ارز',
                value: s.notifyPriceMoves,
                onChanged: canEdit && s.notificationsEnabled
                    ? (v) => _persist(state, (d) => d.notifyPriceMoves = v)
                    : null,
              ),
              TgSettingsSwitchTile(
                icon: Icons.sync_rounded,
                iconColor: const Color(0xFF30B0C7),
                title: 'اجرا در پس‌زمینه',
                subtitle: s.notifyBackground
                    ? 'پایش قیمت و سود حتی وقتی برنامه بسته است'
                    : 'فقط وقتی برنامه باز است',
                value: s.notifyBackground,
                onChanged: canEdit &&
                        s.notificationsEnabled &&
                        (s.notifyPriceMoves || s.notifyTrades)
                    ? (v) => _persist(state, (d) => d.notifyBackground = v)
                    : null,
              ),
              TgSettingsTile(
                icon: Icons.tune_rounded,
                iconColor: const Color(0xFFFF9500),
                title: 'آستانه قیمت ارزها',
                subtitle: s.armedPriceAlertCount > 0
                    ? 'بالاتر / پایین‌تر از مقدار دلخواه'
                    : 'برای هر ارز سقف و کف تنظیم کنید',
                onTap: !canEdit || !s.notificationsEnabled
                    ? null
                    : () {
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const PriceAlertsPage(),
                          ),
                        );
                      },
              ),
              TgSettingsTile(
                icon: Icons.notification_add_rounded,
                iconColor: const Color(0xFF5856D6),
                title: 'ارسال اعلان آزمایشی',
                subtitle: s.notificationsEnabled
                    ? 'برای تست مجوز و کانال اعلان'
                    : 'ابتدا اعلان‌ها را روشن کنید',
                onTap: !canEdit || !s.notificationsEnabled
                    ? null
                    : () async {
                        final permitted = await NotificationService.instance
                            .areNotificationsEnabled();
                        if (!permitted) {
                          final ok = await NotificationService.instance
                              .requestPermission();
                          if (!ok) {
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'اجازه اعلان در سیستم فعال نیست',
                                ),
                              ),
                            );
                            return;
                          }
                        }
                        await NotificationService.instance.showTest();
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('اعلان آزمایشی ارسال شد'),
                          ),
                        );
                      },
                showDivider: false,
              ),
            ],
          ),
          TgSettingsSection(
            title: 'قیمت زنده',
            children: [
              TgSettingsSwitchTile(
                icon: Icons.bolt_rounded,
                iconColor: const Color(0xFFFFCC00),
                title: 'قیمت زنده',
                value: s.livePricesEnabled,
                onChanged: canEdit
                    ? (v) => _persist(
                          state,
                          (d) => d.livePricesEnabled = v,
                        )
                    : null,
              ),
              TgSettingsSwitchTile(
                icon: Icons.currency_exchange_rounded,
                iconColor: const Color(0xFF007AFF),
                title: 'API تتر',
                subtitle: 'Wallex',
                value: s.usdtApiEnabled,
                onChanged: canEdit && s.livePricesEnabled
                    ? (v) => _persist(
                          state,
                          (d) => d.usdtApiEnabled = v,
                        )
                    : null,
              ),
              TgSettingsSwitchTile(
                icon: Icons.diamond_rounded,
                iconColor: const Color(0xFFFF9500),
                title: 'API طلا',
                subtitle: 'PersianToolbox',
                value: s.goldApiEnabled,
                onChanged: canEdit && s.livePricesEnabled
                    ? (v) => _persist(
                          state,
                          (d) => d.goldApiEnabled = v,
                        )
                    : null,
              ),
              TgSettingsTile(
                icon: Icons.sync_rounded,
                iconColor: const Color(0xFF30B0C7),
                title: 'بروزرسانی فوری قیمت‌ها',
                onTap: _busy
                    ? null
                    : () async {
                        setState(() => _busy = true);
                        try {
                          await state.refreshQuotes();
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('قیمت‌ها به‌روز شد'),
                              ),
                            );
                          }
                        } finally {
                          if (mounted) setState(() => _busy = false);
                        }
                      },
                showDivider: false,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            AppConfig.appName,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: AppTheme.muted.withValues(alpha: 0.75),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'تنظیمات روی حساب ذخیره می‌شود',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11,
              color: AppTheme.muted.withValues(alpha: 0.55),
            ),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:invest/config/app_config.dart';
import 'package:invest/domain/models/app_settings.dart';
import 'package:invest/ui/layout/page_padding.dart';
import 'package:invest/ui/pages/app_lock_page.dart';
import 'package:invest/ui/theme/app_theme.dart';
import 'package:invest/ui/widgets/settings_ui.dart';
import 'package:invest/state/app_state.dart';
import 'package:provider/provider.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late AppSettings draft;
  late TextEditingController _serverCtrl;
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    final state = context.read<AppState>();
    draft = _clone(state.settings);
    _serverCtrl = TextEditingController(text: state.baseUrl);
  }

  @override
  void dispose() {
    _serverCtrl.dispose();
    super.dispose();
  }

  AppSettings _clone(AppSettings s) => AppSettings(
        calendar: s.calendar,
        currency: s.currency,
        theme: s.theme,
        livePricesEnabled: s.livePricesEnabled,
        usdtApiEnabled: s.usdtApiEnabled,
        goldApiEnabled: s.goldApiEnabled,
        wallexUrl: s.wallexUrl,
        persianToolboxUrl: s.persianToolboxUrl,
        usdtTmnRate: s.usdtTmnRate,
        goldTmnPerGram: s.goldTmnPerGram,
      );

  void _markDirty() => setState(() => _dirty = true);

  Future<void> _saveDraft(AppState state) async {
    await state.saveSettings(draft);
    if (mounted) {
      setState(() => _dirty = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تنظیمات ذخیره شد')),
      );
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

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final isDark = draft.theme == AppConfig.themeDark;

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: shellPagePadding(),
      children: [
        const SettingsHeroHeader(),
        SettingsSectionCard(
          title: 'امنیت و قفل برنامه',
          subtitle: 'رمز محلی برای ورود — مستقل از OTP وینور',
          icon: Icons.lock_outline_rounded,
          accent: const Color(0xFF5B8DEF),
          children: [
            SettingsTile(
              title: state.appLockEnabled ? 'رمز ورود فعال است' : 'رمز ورود تنظیم نشده',
              subtitle: state.biometricUnlockEnabled
                  ? 'باز شدن با ${state.biometricLabel} فعال است'
                  : 'برای محافظت از داده‌های محلی رمز تعیین کنید',
              trailing: SettingsStatusChip(
                label: state.appLockEnabled ? 'فعال' : 'غیرفعال',
                active: state.appLockEnabled,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
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
                      icon: const Icon(Icons.password_rounded, size: 18),
                      label: Text(
                        state.appLockEnabled ? 'تغییر رمز' : 'تنظیم رمز',
                      ),
                    ),
                  ),
                  if (state.appLockEnabled) ...[
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _removeAppLock(state),
                        icon: const Icon(Icons.delete_outline_rounded, size: 18),
                        label: const Text('حذف رمز'),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (state.biometricAvailable) ...[
              const SettingsDivider(),
              SwitchListTile(
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                secondary: Icon(
                  Icons.fingerprint_rounded,
                  color: state.appLockEnabled
                      ? AppTheme.accent
                      : AppTheme.muted,
                ),
                title: Text(
                  'باز کردن با ${state.biometricLabel}',
                  textAlign: TextAlign.right,
                ),
                subtitle: Text(
                  state.appLockEnabled
                      ? 'بدون وارد کردن رمز، با احراز هویت دستگاه وارد شوید'
                      : 'ابتدا رمز ورود برنامه را تنظیم کنید',
                  textAlign: TextAlign.right,
                  style: const TextStyle(fontSize: 12),
                ),
                value: state.biometricUnlockEnabled,
                onChanged: state.appLockEnabled
                    ? (value) async {
                        final messenger = ScaffoldMessenger.of(context);
                        final ok =
                            await state.setBiometricUnlockEnabled(value);
                        if (!mounted) return;
                        if (!ok && value) {
                          messenger.showSnackBar(
                            SnackBar(
                              content: Text(
                                'فعال‌سازی ${state.biometricLabel} انجام نشد.',
                              ),
                            ),
                          );
                        }
                      }
                    : null,
              ),
            ],
          ],
        ),
        const SizedBox(height: 14),
        if (state.useRemote) ...[
          SettingsSectionCard(
            title: 'حساب وینور',
            subtitle: 'اتصال به سرور و خروج از حساب',
            icon: Icons.cloud_outlined,
            accent: AppTheme.positive,
            children: [
              SettingsTile(
                title: 'شماره موبایل',
                subtitle: state.userPhone ?? '—',
                leading: const Icon(Icons.phone_android_rounded, size: 20),
              ),
              const SettingsDivider(),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: TextField(
                  controller: _serverCtrl,
                  decoration: const InputDecoration(
                    labelText: 'آدرس سرور وینور',
                    hintText: AppConfig.defaultBaseUrl,
                    prefixIcon: Icon(Icons.link_rounded),
                  ),
                  textAlign: TextAlign.left,
                  textDirection: TextDirection.ltr,
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          await state.setBaseUrl(_serverCtrl.text.trim());
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('آدرس سرور ذخیره شد')),
                            );
                          }
                        },
                        icon: const Icon(Icons.save_outlined, size: 18),
                        label: const Text('ذخیره آدرس'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => state.logout(),
                        icon: const Icon(Icons.logout_rounded, size: 18),
                        label: const Text('خروج'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.negative.withValues(alpha: 0.85),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
        ],
        SettingsSectionCard(
          title: 'ظاهر و نمایش',
          subtitle: 'تم، تقویم و واحد پول',
          icon: Icons.palette_outlined,
          accent: const Color(0xFF9B6BFF),
          children: [
            SwitchListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              title: const Text('تم تاریک', textAlign: TextAlign.right),
              subtitle: Text(
                isDark ? 'حالت شب فعال است' : 'حالت روشن فعال است',
                textAlign: TextAlign.right,
                style: const TextStyle(fontSize: 12),
              ),
              value: isDark,
              onChanged: (v) {
                setState(() {
                  draft.theme = v ? AppConfig.themeDark : AppConfig.themeLight;
                  _dirty = true;
                });
              },
            ),
            const SettingsDivider(),
            SettingsTile(
              title: 'تقویم',
              trailing: DropdownButton<String>(
                value: draft.calendar,
                underline: const SizedBox.shrink(),
                items: const [
                  DropdownMenuItem(
                    value: AppConfig.calendarJalali,
                    child: Text('شمسی'),
                  ),
                  DropdownMenuItem(
                    value: AppConfig.calendarGregorian,
                    child: Text('میلادی'),
                  ),
                ],
                onChanged: (v) => setState(() {
                  draft.calendar = v!;
                  _dirty = true;
                }),
              ),
            ),
            const SettingsDivider(),
            SettingsTile(
              title: 'ارز نمایش',
              trailing: DropdownButton<String>(
                value: draft.currency,
                underline: const SizedBox.shrink(),
                items: const [
                  DropdownMenuItem(
                    value: AppConfig.currencyToman,
                    child: Text('تومان'),
                  ),
                  DropdownMenuItem(
                    value: AppConfig.currencyRial,
                    child: Text('ریال'),
                  ),
                  DropdownMenuItem(
                    value: AppConfig.currencyUsd,
                    child: Text('دلار'),
                  ),
                  DropdownMenuItem(
                    value: AppConfig.currencyUsdt,
                    child: Text('تتر'),
                  ),
                ],
                onChanged: (v) => setState(() {
                  draft.currency = v!;
                  _dirty = true;
                }),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        SettingsSectionCard(
          title: 'قیمت زنده',
          subtitle: 'نرخ تتر و طلا از APIهای خارجی',
          icon: Icons.show_chart_rounded,
          accent: const Color(0xFFE8A838),
          children: [
            SwitchListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              title: const Text('فعال‌سازی قیمت زنده', textAlign: TextAlign.right),
              value: draft.livePricesEnabled,
              onChanged: (v) {
                setState(() {
                  draft.livePricesEnabled = v;
                  _markDirty();
                });
              },
            ),
            const SettingsDivider(),
            SwitchListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              title: const Text('API تتر (Wallex)', textAlign: TextAlign.right),
              value: draft.usdtApiEnabled,
              onChanged: draft.livePricesEnabled
                  ? (v) {
                      setState(() {
                        draft.usdtApiEnabled = v;
                        _markDirty();
                      });
                    }
                  : null,
            ),
            const SettingsDivider(),
            SwitchListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              title: const Text(
                'API طلا (PersianToolbox)',
                textAlign: TextAlign.right,
              ),
              value: draft.goldApiEnabled,
              onChanged: draft.livePricesEnabled
                  ? (v) {
                      setState(() {
                        draft.goldApiEnabled = v;
                        _markDirty();
                      });
                    }
                  : null,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
              child: OutlinedButton.icon(
                onPressed: () async {
                  await state.refreshQuotes();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('قیمت‌ها به‌روز شد')),
                    );
                  }
                },
                icon: const Icon(Icons.sync_rounded, size: 18),
                label: const Text('بروزرسانی فوری قیمت‌ها'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        ElevatedButton.icon(
          onPressed: _dirty ? () => _saveDraft(state) : null,
          icon: const Icon(Icons.check_circle_outline_rounded),
          label: Text(_dirty ? 'ذخیره تغییرات' : 'همه‌چیز ذخیره شده'),
          style: ElevatedButton.styleFrom(
            minimumSize: const Size.fromHeight(50),
            backgroundColor: _dirty ? AppTheme.accent : AppTheme.border,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          AppConfig.appName,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12,
            color: AppTheme.muted.withValues(alpha: 0.8),
          ),
        ),
      ],
    );
  }
}

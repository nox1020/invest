import 'package:flutter/material.dart';
import 'package:invest/config/app_config.dart';
import 'package:invest/domain/models/app_settings.dart';
import 'package:invest/ui/pages/app_lock_page.dart';
import 'package:invest/ui/layout/page_padding.dart';
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

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: shellPagePadding(),
      children: [
        const ListTile(
          title: Text('قفل ورود به برنامه', textAlign: TextAlign.right),
        ),
        ListTile(
          title: Text(
            state.appLockEnabled ? 'رمز ورود فعال است' : 'رمز ورود تنظیم نشده',
            textAlign: TextAlign.right,
          ),
          subtitle: const Text(
            'رمز محلی برای باز کردن برنامه — ربطی به OTP وینور ندارد.',
            textAlign: TextAlign.right,
          ),
        ),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
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
                child: Text(
                  state.appLockEnabled ? 'تغییر رمز ورود' : 'تنظیم رمز ورود',
                ),
              ),
            ),
            if (state.appLockEnabled) ...[
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: () async {
                    final appState = context.read<AppState>();
                    final messenger = ScaffoldMessenger.of(context);
                    final pwdCtrl = TextEditingController();
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('حذف رمز ورود'),
                        content: TextField(
                          controller: pwdCtrl,
                          obscureText: true,
                          decoration: const InputDecoration(
                            labelText: 'رمز فعلی',
                          ),
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
                    if (ok != true || !context.mounted) {
                      pwdCtrl.dispose();
                      return;
                    }
                    final valid = await appState.unlockApp(pwdCtrl.text);
                    pwdCtrl.dispose();
                    if (!valid) {
                      if (context.mounted) {
                        messenger.showSnackBar(
                          const SnackBar(content: Text('رمز فعلی نادرست است.')),
                        );
                      }
                      return;
                    }
                    await appState.removeAppLock();
                    if (context.mounted) {
                      messenger.showSnackBar(
                        const SnackBar(content: Text('رمز ورود حذف شد')),
                      );
                    }
                  },
                  child: const Text('حذف رمز'),
                ),
              ),
            ],
          ],
        ),
        const Divider(),
        if (state.useRemote) ...[
          const ListTile(
            title: Text('حساب وینور', textAlign: TextAlign.right),
          ),
          ListTile(
            title: const Text('شماره', textAlign: TextAlign.right),
            trailing: Text(state.userPhone ?? '—'),
          ),
          TextField(
            controller: _serverCtrl,
            decoration: const InputDecoration(
              labelText: 'آدرس سرور وینور',
              hintText: AppConfig.defaultBaseUrl,
            ),
            textAlign: TextAlign.left,
            textDirection: TextDirection.ltr,
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: () async {
              await state.setBaseUrl(_serverCtrl.text.trim());
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('آدرس سرور ذخیره شد')),
                );
              }
            },
            child: const Text('ذخیره آدرس سرور'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: () async {
              await state.logout();
            },
            child: const Text('خروج'),
          ),
          const Divider(),
        ],
        const ListTile(
          title: Text('عمومی', textAlign: TextAlign.right),
        ),
        SwitchListTile(
          title: const Text('تم تاریک', textAlign: TextAlign.right),
          value: draft.theme == AppConfig.themeDark,
          onChanged: (v) => setState(() {
            draft.theme = v ? AppConfig.themeDark : AppConfig.themeLight;
          }),
        ),
        ListTile(
          title: const Text('تقویم', textAlign: TextAlign.right),
          trailing: DropdownButton<String>(
            value: draft.calendar,
            items: const [
              DropdownMenuItem(value: AppConfig.calendarJalali, child: Text('شمسی')),
              DropdownMenuItem(
                  value: AppConfig.calendarGregorian, child: Text('میلادی')),
            ],
            onChanged: (v) => setState(() => draft.calendar = v!),
          ),
        ),
        ListTile(
          title: const Text('ارز نمایش', textAlign: TextAlign.right),
          trailing: DropdownButton<String>(
            value: draft.currency,
            items: const [
              DropdownMenuItem(value: AppConfig.currencyToman, child: Text('تومان')),
              DropdownMenuItem(value: AppConfig.currencyRial, child: Text('ریال')),
              DropdownMenuItem(value: AppConfig.currencyUsd, child: Text('دلار')),
              DropdownMenuItem(value: AppConfig.currencyUsdt, child: Text('تتر')),
            ],
            onChanged: (v) => setState(() => draft.currency = v!),
          ),
        ),
        const Divider(),
        const ListTile(
          title: Text('قیمت زنده', textAlign: TextAlign.right),
        ),
        SwitchListTile(
          title: const Text('فعال‌سازی قیمت زنده', textAlign: TextAlign.right),
          value: draft.livePricesEnabled,
          onChanged: (v) => setState(() => draft.livePricesEnabled = v),
        ),
        SwitchListTile(
          title: const Text('API تتر (Wallex)', textAlign: TextAlign.right),
          value: draft.usdtApiEnabled,
          onChanged: draft.livePricesEnabled
              ? (v) => setState(() => draft.usdtApiEnabled = v)
              : null,
        ),
        SwitchListTile(
          title: const Text('API طلا (PersianToolbox)', textAlign: TextAlign.right),
          value: draft.goldApiEnabled,
          onChanged: draft.livePricesEnabled
              ? (v) => setState(() => draft.goldApiEnabled = v)
              : null,
        ),
        const SizedBox(height: 12),
        ElevatedButton(
          onPressed: () async {
            await state.saveSettings(draft);
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('ذخیره شد')),
              );
            }
          },
          child: const Text('ذخیره تنظیمات'),
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: () async {
            await state.refreshQuotes();
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('قیمت‌ها به‌روز شد')),
              );
            }
          },
          child: const Text('بروزرسانی فوری قیمت‌ها'),
        ),
      ],
    );
  }
}

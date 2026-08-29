import 'package:flutter/material.dart';
import 'package:invest/config/app_config.dart';
import 'package:invest/domain/models/app_settings.dart';
import 'package:invest/state/app_state.dart';
import 'package:provider/provider.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late AppSettings draft;

  @override
  void initState() {
    super.initState();
    draft = _clone(context.read<AppState>().settings);
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
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
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
            final state = context.read<AppState>();
            await state.saveSettings(draft);
            await state.refreshQuotes();
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
            await context.read<AppState>().refreshQuotes();
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

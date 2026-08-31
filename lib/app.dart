import 'package:flutter/material.dart';
import 'package:invest/config/app_config.dart';
import 'package:invest/state/app_state.dart';
import 'package:invest/ui/pages/assets_page.dart';
import 'package:invest/ui/pages/dashboard_page.dart';
import 'package:invest/ui/pages/login_page.dart';
import 'package:invest/ui/pages/settings_page.dart';
import 'package:invest/ui/pages/trades_page.dart';
import 'package:invest/ui/theme/app_theme.dart';
import 'package:provider/provider.dart';

class InvestApp extends StatelessWidget {
  const InvestApp({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return MaterialApp(
      title: AppConfig.appName,
      debugShowCheckedModeBanner: false,
      theme: state.settings.isDark ? AppTheme.dark() : AppTheme.light(),
      locale: const Locale('fa', 'IR'),
      builder: (context, child) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: state.authenticated ? const HomeShell() : const LoginPage(),
    );
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int index = 0;

  static const titles = [
    'داشبورد',
    'دارایی‌ها',
    'معاملات باز',
    'معاملات بسته',
    'تنظیمات',
  ];

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final pages = [
      const DashboardPage(),
      const AssetsPage(),
      const TradesPage(open: true),
      const TradesPage(open: false),
      const SettingsPage(),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(titles[index]),
        actions: [
          IconButton(
            tooltip: 'بروزرسانی',
            onPressed: state.loading
                ? null
                : () async {
                    await state.refreshQuotes();
                    await state.refresh();
                  },
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: state.loading && state.metrics == null
          ? const Center(child: CircularProgressIndicator())
          : IndexedStack(index: index, children: pages),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: index,
        onTap: (i) => setState(() => index = i),
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.dashboard_outlined),
            label: 'داشبورد',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.account_balance_wallet_outlined),
            label: 'دارایی',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.trending_up),
            label: 'باز',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.history),
            label: 'بسته',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings_outlined),
            label: 'تنظیمات',
          ),
        ],
      ),
    );
  }
}

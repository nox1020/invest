import 'package:flutter/material.dart';
import 'package:invest/config/app_config.dart';
import 'package:invest/state/app_state.dart';
import 'package:invest/ui/pages/assets_page.dart';
import 'package:invest/ui/pages/dashboard_page.dart';
import 'package:invest/ui/pages/app_lock_page.dart';
import 'package:invest/ui/pages/login_page.dart';
import 'package:invest/ui/widgets/app_logo.dart';
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
      home: _homeFor(state),
    );
  }

  Widget _homeFor(AppState state) {
    if (state.loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (state.appLockEnabled && !state.appUnlocked) {
      return const AppLockPage();
    }
    if (state.authenticated) {
      return const HomeShell();
    }
    return const LoginPage();
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int index = 0;
  bool _refreshing = false;

  static const titles = [
    'داشبورد',
    'دارایی‌ها',
    'معاملات باز',
    'معاملات بسته',
    'تنظیمات',
  ];

  Future<void> _refreshAll(AppState state) async {
    if (_refreshing) return;
    setState(() => _refreshing = true);
    try {
      await state.refreshAll();
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  Widget? _floatingActionButton(BuildContext context) {
    switch (index) {
      case 1:
        return FloatingActionButton.extended(
          onPressed: () => showAssetEditor(context),
          icon: const Icon(Icons.add),
          label: const Text('دارایی جدید'),
        );
      case 2:
        return FloatingActionButton.extended(
          onPressed: () => showBuyTradeDialog(context),
          icon: const Icon(Icons.add_shopping_cart),
          label: const Text('خرید'),
        );
      default:
        return null;
    }
  }

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

    final initialLoad = state.loading && state.metrics == null;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const AppMark(size: 26),
            const SizedBox(width: 10),
            Text(titles[index]),
          ],
        ),
        actions: [
          if (_refreshing)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else
            IconButton(
              tooltip: 'بروزرسانی',
              onPressed: () => _refreshAll(state),
              icon: const Icon(Icons.refresh),
            ),
        ],
      ),
      body: initialLoad
          ? const Center(child: CircularProgressIndicator())
          : IndexedStack(
              index: index,
              sizing: StackFit.expand,
              children: pages,
            ),
      floatingActionButton: initialLoad ? null : _floatingActionButton(context),
      floatingActionButtonLocation: FloatingActionButtonLocation.startFloat,
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: index,
        onTap: (i) => setState(() => index = i),
        type: BottomNavigationBarType.fixed,
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

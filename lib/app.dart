import 'package:flutter/material.dart';
import 'package:invest/config/app_config.dart';
import 'package:invest/state/app_state.dart';
import 'package:invest/ui/layout/home_tabs.dart';
import 'package:invest/ui/pages/dashboard_page.dart';
import 'package:invest/ui/pages/app_lock_page.dart';
import 'package:invest/ui/pages/login_page.dart';
import 'package:invest/ui/widgets/app_logo.dart';
import 'package:invest/ui/pages/commodity_index_page.dart';
import 'package:invest/ui/pages/trades_hub_page.dart';
import 'package:invest/ui/pages/withdrawals_page.dart';
import 'package:invest/ui/pages/settings_page.dart';
import 'package:invest/ui/theme/app_theme.dart';
import 'package:invest/ui/widgets/asset_editor_sheet.dart';
import 'package:invest/ui/widgets/connection_status_title.dart';
import 'package:invest/ui/widgets/offline_banner.dart';
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

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  int index = 0;

  static const titles = [
    'داشبورد',
    'برداشت',
    'معاملات',
    'شاخص',
    'تنظیمات',
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      context.read<AppState>().onAppResumed();
    }
  }

  Future<void> _refreshAll(AppState state) async {
    if (state.offline) {
      final ok = await state.tryGoOnline();
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('هنوز آفلاین هستید — داده‌های ذخیره‌شده نمایش داده می‌شود'),
          ),
        );
      }
      if (index == HomeTabs.index) {
        await state.refreshCommodityIndex(force: true);
      }
      return;
    }
    await state.refreshAll();
    if (index == HomeTabs.index) {
      await state.refreshCommodityIndex(force: true);
    }
  }

  Widget? _floatingActionButton(BuildContext context) {
    final state = context.read<AppState>();
    if (!state.canMutate) return null;
    switch (index) {
      case HomeTabs.trades:
        return FloatingActionButton.extended(
          onPressed: () => showAssetEditor(context),
          icon: const Icon(Icons.add),
          label: const Text('دارایی جدید'),
        );
      case HomeTabs.withdrawals:
        return FloatingActionButton.extended(
          onPressed: () => showRecordWithdrawalDialog(context),
          icon: const Icon(Icons.south_west_rounded),
          label: const Text('ثبت برداشت'),
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
      const WithdrawalsPage(),
      const TradesHubPage(),
      const CommodityIndexPage(),
      const SettingsPage(),
    ];

    final initialLoad = state.loading && state.metrics == null;
    final updating =
        state.refreshing || (index == HomeTabs.index && state.commodityIndexLoading);
    final connectionStatus = AppConnectionStatus.resolve(
      offline: state.offline,
      updating: updating,
    );

    return Scaffold(
      appBar: AppBar(
        centerTitle: false,
        titleSpacing: 16,
        title: Row(
          children: [
            const AppMark(size: 26),
            const SizedBox(width: 10),
            Expanded(
              child: ConnectionStatusTitle(
                pageTitle: titles[index],
                status: connectionStatus,
              ),
            ),
          ],
        ),
        flexibleSpace: updating
            ? const Align(
                alignment: Alignment.bottomCenter,
                child: ConnectionProgressBar(),
              )
            : null,
        actions: [
          IconButton(
            tooltip: state.offline ? 'تلاش برای اتصال' : 'بروزرسانی',
            onPressed: updating ? null : () => _refreshAll(state),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: initialLoad
          ? const Center(child: CircularProgressIndicator())
          : NotificationListener<OpenHomeTabNotification>(
              onNotification: (n) {
                setState(() => index = n.index);
                if (n.index == HomeTabs.index) {
                  context.read<AppState>().refreshCommodityIndex(force: false);
                }
                return true;
              },
              child: Column(
                children: [
                  if (state.readOnlyOffline) const OfflineReadOnlyNotice(),
                  Expanded(
                    child: IndexedStack(
                      index: index,
                      sizing: StackFit.expand,
                      children: pages,
                    ),
                  ),
                ],
              ),
            ),
      floatingActionButton: initialLoad ? null : _floatingActionButton(context),
      floatingActionButtonLocation: FloatingActionButtonLocation.startFloat,
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: index,
        onTap: (i) {
          setState(() => index = i);
          if (i == HomeTabs.index) {
            context.read<AppState>().refreshCommodityIndex(force: false);
          }
        },
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.dashboard_outlined),
            label: 'داشبورد',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.payments_outlined),
            label: 'برداشت',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.swap_horiz_rounded),
            label: 'معاملات',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.insights_outlined),
            label: 'شاخص',
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

import 'package:flutter/material.dart';
import 'package:invest/ui/pages/global_search_page.dart';
import 'package:invest/ui/widgets/bank_sms_ui.dart';
import 'package:invest/config/app_config.dart';
import 'package:invest/data/notification_inbox_store.dart';
import 'package:invest/state/app_state.dart';
import 'package:invest/ui/layout/home_tabs.dart';
import 'package:invest/ui/pages/dashboard_page.dart';
import 'package:invest/ui/pages/app_lock_page.dart';
import 'package:invest/ui/pages/login_page.dart';
import 'package:invest/ui/pages/notifications_page.dart';
import 'package:invest/ui/pages/performance_page.dart';
import 'package:invest/ui/pages/trades_hub_page.dart';
import 'package:invest/ui/pages/withdrawals_page.dart';
import 'package:invest/ui/pages/settings_page.dart';
import 'package:invest/ui/theme/app_theme.dart';
import 'package:invest/ui/widgets/asset_editor_sheet.dart';
import 'package:invest/ui/widgets/connection_status_title.dart';
import 'package:invest/ui/widgets/header_status.dart';
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
    'عملکرد',
    'تنظیمات',
  ];

  void _goTab(int i) {
    if (!mounted || i < 0 || i >= titles.length) return;
    setState(() => index = i);
  }

  @override
  void initState() {
    super.initState();
    homeTabSwitcher = _goTab;
    WidgetsBinding.instance.addObserver(this);
    NotificationInboxStore.ensureHydrated();
  }

  @override
  void dispose() {
    if (homeTabSwitcher == _goTab) homeTabSwitcher = null;
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      context.read<AppState>().onAppResumed();
    }
  }

  void _openNotifications() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const NotificationsPage(),
      ),
    );
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
  Widget build(BuildContext context) =>
      BankSmsWatcher(child: Builder(builder: _buildShell));

  Widget _buildShell(BuildContext context) {
    final state = context.watch<AppState>();
    final pages = [
      const DashboardPage(),
      const WithdrawalsPage(),
      const TradesHubPage(),
      const PerformancePage(),
      const SettingsPage(),
    ];

    final initialLoad = state.loading && state.metrics == null;
    final updating = state.refreshing;

    return Scaffold(
      appBar: AppBar(
        centerTitle: false,
        titleSpacing: 16,
        title: HeaderStatusTitle(
          title: titles[index],
          alwaysShow: true,
        ),
        flexibleSpace: updating && !state.offline
            ? const Align(
                alignment: Alignment.bottomCenter,
                child: ConnectionProgressBar(),
              )
            : null,
        actions: [
          if (index == HomeTabs.dashboard)
            IconButton(
              key: const ValueKey('dash-search'),
              tooltip: 'جستجو',
              onPressed: () => openGlobalSearch(context),
              icon: const Icon(Icons.search_rounded),
            ),
          ValueListenableBuilder<int>(
            valueListenable: NotificationInboxStore.unreadCount,
            builder: (context, unread, _) {
              return IconButton(
                tooltip: 'اعلان‌ها',
                onPressed: _openNotifications,
                icon: Badge(
                  isLabelVisible: unread > 0,
                  label: Text(unread > 99 ? '99+' : '$unread'),
                  child: const Icon(Icons.notifications_outlined),
                ),
              );
            },
          ),
        ],
      ),
      body: initialLoad
          ? const Center(child: CircularProgressIndicator())
          : NotificationListener<OpenHomeTabNotification>(
              onNotification: (n) {
                _goTab(n.index);
                return true;
              },
              child: Column(
                children: [
                  // Connection / sync notices live in the header line only.
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
        onTap: _goTab,
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
            icon: Icon(Icons.query_stats_rounded),
            label: 'عملکرد',
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

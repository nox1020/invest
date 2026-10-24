import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:invest/config/app_config.dart';
import 'package:invest/data/invest_api_client.dart';
import 'package:invest/data/session_store.dart';
import 'package:invest/domain/models/app_settings.dart';
import 'package:invest/domain/models/asset.dart';
import 'package:invest/state/app_state.dart';
import 'package:invest/ui/pages/dashboard_page.dart';
import 'package:invest/ui/widgets/connection_status_title.dart';
import 'package:invest/ui/widgets/offline_banner.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

AppState _state({
  bool offline = true,
  bool readOnly = true,
  bool remote = true,
  bool reauth = false,
  OfflineCause? cause,
}) =>
    AppState()
      ..loading = false
      ..authenticated = true
      ..useRemote = remote
      ..offline = offline
      ..readOnlyOffline = readOnly
      ..reauthRequired = reauth
      ..offlineCause = cause
      ..lastSyncedAt = DateTime(2026, 10, 24, 8, 42)
      ..settings = AppSettings(calendar: AppConfig.calendarJalali);

Widget _host(AppState s, Widget child) => ChangeNotifierProvider.value(
      value: s,
      child: MaterialApp(
        builder: (c, w) =>
            Directionality(textDirection: TextDirection.rtl, child: w!),
        home: child,
      ),
    );

class _Page extends StatelessWidget {
  const _Page({this.queues = false});
  final bool queues;
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
            title: const Text('چک‌ها'),
            bottom: connectionStripFor(context, queuesWrites: queues)),
        body: Builder(
          builder: (c) => TextButton(
              onPressed: () => showReadOnlySnack(c), child: const Text('ثبت')),
        ),
      );
}

void main() {
  group('resolve', () {
    test('every state maps to one status', () {
      AppConnectionStatus r(
              {bool off = false,
              bool up = false,
              bool local = false,
              bool re = false,
              OfflineCause? c}) =>
          AppConnectionStatus.resolve(
              offline: off,
              updating: up,
              localOnly: local,
              reauth: re,
              cause: c);
      expect(r(), AppConnectionStatus.connected);
      expect(r(up: true), AppConnectionStatus.updating);
      expect(r(off: true), AppConnectionStatus.waitingNetwork);
      expect(r(off: true, c: OfflineCause.network),
          AppConnectionStatus.waitingNetwork);
      expect(
          r(off: true, c: OfflineCause.server), AppConnectionStatus.serverDown);
      // A background probe while offline must not flash «به‌روزرسانی».
      expect(r(off: true, up: true, c: OfflineCause.server),
          AppConnectionStatus.connecting);
      expect(r(off: true, re: true), AppConnectionStatus.reauth);
      expect(r(off: true, up: true, re: true), AppConnectionStatus.reauth);
      expect(r(off: true, local: true), AppConnectionStatus.localOnly);
      expect(AppConnectionStatus.connected.isOnline, isTrue);
      expect(AppConnectionStatus.serverDown.isOnline, isFalse);
      // Offline is amber, never the error red.
      expect(AppConnectionStatus.waitingNetwork.color,
          AppConnectionStatus.serverDown.color);
    });

    test('offline cause: transport vs server answer', () {
      expect(
          offlineCauseOf(InvestApiException('x', errorCode: 'network_error')),
          OfflineCause.network);
      expect(offlineCauseOf(InvestApiException('x', statusCode: 502)),
          OfflineCause.server);
      expect(
          offlineCauseOf(
              InvestApiException('x', statusCode: 302, errorCode: 'redirect')),
          OfflineCause.server);
      expect(offlineCauseOf(StateError('?')), OfflineCause.network);
    });
  });

  group('auth check cause', () {
    Future<AuthCheckResult> check(MockClient c) async {
      SharedPreferences.setMockInitialValues({
        AppConfig.prefBaseUrl: 'https://vinor.test',
        AppConfig.prefSessionCookie: 'vinor_session=t',
      });
      final session = await SessionStore.load();
      final api = InvestApiClient(session, client: c)..restoreSessionCookie();
      return api.checkAuthDetailed();
    }

    test('no internet → network', () async {
      final r = await check(
          MockClient((_) async => throw http.ClientException('down')));
      expect(r.status, AuthCheckStatus.offline);
      expect(r.cause, OfflineCause.network);
    });

    test('5xx → server down, session kept', () async {
      final r =
          await check(MockClient((_) async => http.Response('oops', 503)));
      expect(r.status, AuthCheckStatus.offline);
      expect(r.cause, OfflineCause.server);
    });
  });

  group('AppState', () {
    test('connectionStatus follows flags; no pending writes by default', () {
      expect(_state().connectionStatus, AppConnectionStatus.waitingNetwork);
      expect(_state(cause: OfflineCause.server).connectionStatus,
          AppConnectionStatus.serverDown);
      expect(_state(reauth: true).connectionStatus, AppConnectionStatus.reauth);
      expect(_state(remote: false, readOnly: false).connectionStatus,
          AppConnectionStatus.localOnly);
      expect(_state(offline: false, readOnly: false).connectionStatus,
          AppConnectionStatus.connected);
      expect(_state().pendingWrites, 0);
    });

    test('read-only message names the real reason', () {
      expect(readOnlyMessage(_state(reauth: true)), contains('دوباره وارد'));
      expect(readOnlyMessage(_state(cause: OfflineCause.server)),
          contains('سرور در دسترس نیست'));
      expect(readOnlyMessage(_state()), contains('آفلاین'));
    });
  });

  group('UI', () {
    testWidgets('title shows queued count', (t) async {
      await t.pumpWidget(const MaterialApp(
          home: Scaffold(
              body: ConnectionStatusTitle(
                  pageTitle: 'داشبورد',
                  status: AppConnectionStatus.waitingNetwork,
                  pending: 2))));
      expect(find.text('آفلاین · در انتظار شبکه — ۲ تغییر در صف'), findsOneWidget);
    });

    testWidgets('notice: reason, last sync, retry; hidden online/reauth',
        (t) async {
      await t.pumpWidget(_host(_state(cause: OfflineCause.server),
          const Scaffold(body: OfflineReadOnlyNotice())));
      expect(find.textContaining('سرور پاسخ نمی‌دهد'), findsOneWidget);
      expect(find.textContaining('۰۸:۴۲'), findsOneWidget);
      expect(find.text('تلاش دوباره'), findsOneWidget);

      await t.pumpWidget(_host(_state(remote: false, readOnly: false),
          const Scaffold(body: OfflineReadOnlyNotice())));
      expect(find.textContaining('حالت محلی'), findsOneWidget);
      expect(find.text('اتصال به سرور'), findsOneWidget);

      for (final s in [
        _state(offline: false, readOnly: false),
        _state(reauth: true),
      ]) {
        await t.pumpWidget(
            _host(s, const Scaffold(body: OfflineReadOnlyNotice())));
        expect(find.byKey(const ValueKey('offline-notice')), findsNothing);
      }
    });

    testWidgets('notice retry probes the server and disables while busy',
        (t) async {
      final s = _state();
      await t
          .pumpWidget(_host(s, const Scaffold(body: OfflineReadOnlyNotice())));
      s.refreshing = true;
      s.notifyListeners();
      await t.pump();
      expect(find.text('در حال اتصال…'), findsOneWidget);
      final b =
          t.widget<TextButton>(find.byKey(const ValueKey('offline-retry')));
      expect(b.onPressed, isNull);
    });

    testWidgets('pushed pages: strip only while offline, honest wording',
        (t) async {
      await t.pumpWidget(_host(_state(), const _Page()));
      expect(find.text('آفلاین · در انتظار شبکه · فقط مشاهده'), findsOneWidget);

      await t.pumpWidget(_host(_state(), const _Page(queues: true)));
      expect(find.text('آفلاین · در انتظار شبکه · تغییرات در صف می‌ماند'),
          findsOneWidget);

      await t.pumpWidget(_host(_state(reauth: true), const _Page()));
      expect(find.text('نیاز به ورود دوباره'), findsOneWidget);

      await t.pumpWidget(
          _host(_state(offline: false, readOnly: false), const _Page()));
      expect(find.byKey(const ValueKey('conn-strip')), findsNothing);

      // Standalone page without AppState: no crash, no strip.
      await t.pumpWidget(const MaterialApp(home: _Page()));
      expect(find.byKey(const ValueKey('conn-strip')), findsNothing);
    });

    testWidgets('read-only snackbar uses the shared reason', (t) async {
      await t.pumpWidget(_host(_state(reauth: true), const _Page()));
      await t.tap(find.text('ثبت'));
      await t.pump();
      expect(find.textContaining('نشست سرور منقضی'), findsOneWidget);
    });
  });

  group('dashboard consistency', () {
    Future<void> pumpDash(WidgetTester t, AppState s) async {
      s.assets = [
        Asset(
            id: 1,
            name: 'Gold',
            symbol: 'GOLD',
            quantity: 1,
            avgBuyPrice: 1,
            currentPrice: 2),
      ];
      t.view.physicalSize = const Size(420, 1400);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      await t.pumpWidget(_host(s, const Scaffold(body: DashboardPage())));
      for (var i = 0; i < 10; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
    }

    String tag(WidgetTester t) {
      final w = find.descendant(
          of: find.byKey(const ValueKey('dash-sync')),
          matching: find.byType(Text));
      return t.widget<Text>(w.first).data!;
    }

    testWidgets('read-only offline: tag, card label, FAB hidden', (t) async {
      await pumpDash(t, _state());
      expect(tag(t), 'آفلاین');
      expect(find.text('دادهٔ ذخیره‌شده · همگام‌سازی ۰۸:۴۲'), findsOneWidget);
      expect(find.byKey(const ValueKey('fab-main')), findsNothing);
    });

    testWidgets('session expired: tag says so, FAB hidden', (t) async {
      await pumpDash(t, _state(reauth: true));
      expect(tag(t), 'ورود لازم');
      expect(find.byKey(const ValueKey('fab-main')), findsNothing);
    });

    testWidgets('local workspace is writable: «محلی», FAB shown', (t) async {
      await pumpDash(t, _state(remote: false, readOnly: false));
      expect(tag(t), 'محلی');
      expect(find.byKey(const ValueKey('fab-main')), findsOneWidget);
    });

    testWidgets('online: synced tag and FAB', (t) async {
      await pumpDash(t, _state(offline: false, readOnly: false));
      expect(tag(t), startsWith('به‌روز'));
      expect(find.byKey(const ValueKey('pv-offline')), findsNothing);
      expect(find.byKey(const ValueKey('fab-main')), findsOneWidget);
    });
  });
}

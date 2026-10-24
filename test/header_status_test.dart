import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:invest/config/app_config.dart';
import 'package:invest/domain/models/app_settings.dart';
import 'package:invest/domain/services/connection_status.dart';
import 'package:invest/state/app_state.dart';
import 'package:invest/ui/widgets/header_status.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

AppState _s({
  bool offline = false,
  bool reauth = false,
  bool remote = true,
  bool refreshing = false,
  String? error,
}) =>
    AppState()
      ..loading = false
      ..authenticated = true
      ..useRemote = remote
      ..offline = offline
      ..readOnlyOffline = offline && remote
      ..reauthRequired = reauth
      ..refreshing = refreshing
      ..error = error
      ..lastSyncedAt = DateTime(2026, 10, 24, 11, 29)
      ..settings = AppSettings(calendar: AppConfig.calendarJalali);

Widget _host(AppState s, {bool always = true}) => ChangeNotifierProvider.value(
      value: s,
      child: MaterialApp(
        builder: (c, w) =>
            Directionality(textDirection: TextDirection.rtl, child: w!),
        home: Scaffold(
          appBar: AppBar(
              title: HeaderStatusTitle(title: 'معاملات', alwaysShow: always)),
        ),
      ),
    );

String _label(WidgetTester t) =>
    t.widget<Text>(find.byKey(const ValueKey('header-status-text'))).data!;

void main() {
  test('header label is exactly one of three words', () {
    const allowed = {'متصل', 'آفلاین', 'در حال بروزرسانی'};
    for (final c in AppConnectionStatus.values) {
      for (final e in [false, true]) {
        for (final sy in [false, true]) {
          for (final p in [0, 3]) {
            final h =
                HeaderStatus.of(conn: c, error: e, syncing: sy, pending: p);
            expect(allowed, contains(h.text), reason: '$c $e $sy $p');
          }
        }
      }
    }
    expect(HeaderStatus.of(conn: AppConnectionStatus.connecting).text,
        'در حال بروزرسانی');
    expect(
        HeaderStatus.of(conn: AppConnectionStatus.serverDown).text, 'آفلاین');
    expect(
        HeaderStatus.of(conn: AppConnectionStatus.connected, error: true).text,
        'آفلاین');
    final re = HeaderStatus.of(conn: AppConnectionStatus.reauth);
    expect(re.text, 'آفلاین');
    expect(re.tone, HeaderTone.bad);
    expect(HeaderStatus.of(conn: AppConnectionStatus.connected).ok, isTrue);
    expect(HeaderStatus.of(conn: AppConnectionStatus.connected, pending: 2).ok,
        isFalse);
  });

  testWidgets('header shows one word; no raw error anywhere', (t) async {
    await t.pumpWidget(_host(_s()));
    expect(_label(t), 'متصل');
    await t.pumpWidget(_host(_s(offline: true, refreshing: true)));
    expect(_label(t), 'در حال بروزرسانی');
    await t.pumpWidget(
        _host(_s(error: 'assets: InvestApiException(/network_error)')));
    expect(_label(t), 'آفلاین');
    expect(find.textContaining('InvestApiException'), findsNothing);
  });

  testWidgets('tap opens details with retry; reauth offers login', (t) async {
    await t.pumpWidget(_host(_s(
        offline: true, error: 'assets: InvestApiException(/network_error)')));
    await t.tap(find.byKey(const ValueKey('header-status')));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('status-sheet')), findsOneWidget);
    expect(find.byKey(const ValueKey('sheet-retry')), findsOneWidget);
    expect(find.textContaining('۱۱:۲۹'), findsOneWidget);
    expect(find.textContaining('InvestApiException'), findsNothing);
    await t.tapAt(const Offset(10, 10)); // scrim closes the sheet
    await t.pumpAndSettle();

    await t.pumpWidget(_host(_s(offline: true, reauth: true)));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('header-status')));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('sheet-login')), findsOneWidget);
    expect(find.byKey(const ValueKey('sheet-retry')), findsNothing);
  });

  testWidgets('pushed pages hide the line while all is well', (t) async {
    await t.pumpWidget(_host(_s(), always: false));
    expect(find.byKey(const ValueKey('header-status')), findsNothing);
    await t.pumpWidget(_host(_s(offline: true), always: false));
    expect(_label(t), 'آفلاین');
  });

  test('offline but not read-only still probes and reconnects', () async {
    SharedPreferences.setMockInitialValues({
      AppConfig.prefBaseUrl: 'https://vinor.test',
      AppConfig.prefSessionCookie: 'vinor_session=t',
    });
    var authCalls = 0;
    final client = MockClient((req) async {
      if (req.url.path.endsWith('/auth/status')) {
        authCalls++;
        return http.Response(jsonEncode({'authenticated': true}), 200,
            headers: {'content-type': 'application/json'});
      }
      if (req.url.path.endsWith('/auth/request-otp') ||
          req.url.path.contains('otp')) {
        return http.Response(jsonEncode({'ok': true}), 200,
            headers: {'content-type': 'application/json'});
      }
      return http.Response(jsonEncode({'items': []}), 200,
          headers: {'content-type': 'application/json'});
    });
    final s = AppState(httpClient: client);
    try {
      await s.requestOtp('09120000000'); // builds the API client
    } catch (_) {}
    s
      ..loading = false
      ..authenticated = true
      ..useRemote = true
      ..offline = true
      ..readOnlyOffline = false // the 1.0.208 stuck state
      ..settings = AppSettings(calendar: AppConfig.calendarJalali);
    await s.refreshAll(
        includeQuotes: false, fetchSettings: false, checkApiVersion: false);
    expect(authCalls, greaterThan(0));
    expect(s.offline, isFalse);
  });
}

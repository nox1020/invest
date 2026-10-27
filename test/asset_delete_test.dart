import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:invest/config/app_config.dart';
import 'package:invest/data/invest_api_client.dart';
import 'package:invest/data/remote_invest_service.dart';
import 'package:invest/data/session_store.dart';
import 'package:invest/domain/models/app_settings.dart';
import 'package:invest/domain/models/asset.dart';
import 'package:invest/domain/models/trade.dart';
import 'package:invest/state/app_state.dart';
import 'package:invest/ui/widgets/asset_delete.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class Server {
  bool down = true;
  final purges = <String>[];
  final keys = <String>{};
  int other = 0;
  Future<http.Response> handle(http.Request r) async {
    if (down) throw http.ClientException('offline');
    final k = r.headers['Idempotency-Key'];
    if (r.url.path.endsWith('/purge')) {
      if (k == null || keys.add(k)) purges.add('${r.url.path} ${r.body}');
    } else if (r.method != 'GET') {
      other++;
    }
    return http.Response(jsonEncode({'success': true, 'items': [], 'deleted': true}), 200,
        headers: {'content-type': 'application/json; charset=utf-8'});
  }
}

const phone = '09120000000';

Future<AppState> _state(Server s) async {
  final session = await SessionStore.load();
  final api = InvestApiClient(session, client: MockClient(s.handle))..restoreSessionCookie();
  return AppState()
    ..loading = false
    ..authenticated = true
    ..useRemote = true
    ..offline = true
    ..readOnlyOffline = true
    ..userPhone = phone
    ..remote = RemoteInvestService(api)
    ..assets = [Asset(id: 5, name: 'طلا', currentPrice: 12, quantity: 2, avgBuyPrice: 10), Asset(id: 6, name: 'دلار', currentPrice: 3, quantity: 1, avgBuyPrice: 2)]
    ..openTrades = [
      Trade(id: 50, assetId: 5, status: AppConfig.tradeOpen, quantity: 2, buyPrice: 10, assetName: 'طلا', currentPrice: 12),
      Trade(id: 60, assetId: 6, status: AppConfig.tradeOpen, quantity: 1, buyPrice: 2, assetName: 'دلار', currentPrice: 3),
    ]
    ..closedTrades = [
      Trade(id: 51, assetId: 5, status: AppConfig.tradeClosed, quantity: 1, buyPrice: 8, sellPrice: 11, realizedPnl: 3, assetName: 'طلا'),
    ]
    ..settings = AppSettings(calendar: AppConfig.calendarJalali);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({
        AppConfig.prefBaseUrl: 'https://vinor.test',
        AppConfig.prefSessionCookie: 'vinor_session=t',
      }));

  test('offline delete: asset and its trades leave totals at once, purge sent once on reconnect', () async {
    final server = Server();
    final s = await _state(server);
    expect(s.realizedBreakdown.trades, 3);
    await s.tradeService.deleteAsset(5);
    s.notifyListeners();
    expect(s.assets.map((a) => a.id), [6]);
    expect(s.openTrades.map((t) => t.id), [60]);
    expect(s.closedTrades, isEmpty);
    expect(s.realizedBreakdown.trades, 0);
    expect(s.pendingWrites, 1);

    // restart: still pending and still hidden
    final s2 = await _state(server);
    await s2.coreOutbox.bind(phone);
    s2.notifyListeners();
    expect(s2.assets.map((a) => a.id), [6]);

    server.down = false;
    s2
      ..offline = false
      ..readOnlyOffline = false;
    expect(await s2.flushCoreOutbox(), isTrue);
    expect(await s2.flushCoreOutbox(), isTrue);
    expect(server.purges, ['/invest/api/v1/assets/5/purge {"confirm":true}']);
    expect(s2.coreOutbox.isEmpty, isTrue);
  });

  test('deleting an asset created offline sends nothing', () async {
    final server = Server();
    final s = await _state(server);
    final a = await s.tradeService.createAsset(name: 'نقره', quantity: 1, avgBuyPrice: 4);
    s.notifyListeners();
    expect(a.id, lessThan(0));
    await s.tradeService.registerBuy(assetId: a.id, quantity: 1, buyPrice: 5);
    s.notifyListeners();
    expect(s.assets.any((x) => x.id == a.id), isTrue);
    await s.tradeService.deleteAsset(a.id!);
    s.notifyListeners();
    expect(s.assets.map((x) => x.id), [5, 6]);
    expect(s.openTrades.every((t) => t.assetId != a.id), isTrue);
    expect(s.coreOutbox.isEmpty, isTrue);
    server.down = false;
    s
      ..offline = false
      ..readOnlyOffline = false;
    expect(await s.flushCoreOutbox(), isTrue);
    expect(server.purges, isEmpty);
    expect(server.other, 0);
  });

  testWidgets('confirmation says what goes; cancel keeps everything', (tester) async {
    final server = Server();
    late AppState s;
    await tester.runAsync(() async => s = await _state(server));
    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: s,
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (ctx) => TextButton(
              onPressed: () => confirmDeleteAsset(ctx, s.assets.first),
              child: const Text('go'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(find.text('حذف دارایی «طلا»'), findsOneWidget);
    expect(find.textContaining('1 معامله باز'), findsOneWidget);
    expect(find.textContaining('1 معامله بسته'), findsOneWidget);
    await tester.tap(find.text('انصراف'));
    await tester.pumpAndSettle();
    expect(s.assets.length, 2);
    expect(s.coreOutbox.isEmpty, isTrue);
  });
}

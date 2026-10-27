import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:invest/config/app_config.dart';
import 'package:invest/data/invest_api_client.dart';
import 'package:invest/data/remote_invest_service.dart';
import 'package:invest/data/session_store.dart';
import 'package:invest/domain/models/app_settings.dart';
import 'package:invest/domain/models/asset.dart';
import 'package:invest/state/app_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

class Server {
  bool down = true;
  final buys = <String>[];
  final keys = <String>{};
  Future<http.Response> handle(http.Request r) async {
    if (down) throw http.ClientException('offline');
    final k = r.headers['Idempotency-Key'];
    if (r.url.path.endsWith('/trades/buy')) {
      if (k == null || keys.add(k)) buys.add(r.body);
      return http.Response(jsonEncode({'success': true, 'item': {'id': 77, 'asset_id': 5, 'status': 'open', 'quantity': 2, 'buy_price': 10}}), 200,
          headers: {'content-type': 'application/json; charset=utf-8'});
    }
    return http.Response(jsonEncode({'success': true}), 200, headers: {'content-type': 'application/json; charset=utf-8'});
  }
}

Future<AppState> _state(Server s) async {
  final session = await SessionStore.load();
  final api = InvestApiClient(session, client: MockClient(s.handle))..restoreSessionCookie();
  return AppState()
    ..loading = false
    ..authenticated = true
    ..useRemote = true
    ..offline = true
    ..readOnlyOffline = true
    ..userPhone = '09120000000'
    ..remote = RemoteInvestService(api)
    ..assets = [Asset(id: 5, name: 'طلا', currentPrice: 12)]
    ..settings = AppSettings(calendar: AppConfig.calendarJalali);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({
        AppConfig.prefBaseUrl: 'https://vinor.test',
        AppConfig.prefSessionCookie: 'vinor_session=t',
      }));

  test('offline buy: editable, shown at once, survives restart, sent once on reconnect', () async {
    final server = Server();
    final s = await _state(server);
    expect(s.canMutate, isTrue); // offline is no longer read-only
    final t = await s.tradeService.registerBuy(assetId: 5, quantity: 2, buyPrice: 10);
    expect(t.id, lessThan(0));
    expect(s.openTrades.single.quantity, 2);
    expect(s.assets.single.quantity, 2); // holdings follow the pending lot
    expect(s.pendingWrites, 1);
    expect(server.buys, isEmpty);

    // app killed: a new process sees the same pending lot
    final s2 = await _state(server);
    await s2.coreOutbox.bind('09120000000');
    s2.notifyListeners();
    expect(s2.openTrades.single.id, lessThan(0));

    // reconnect: flushed once with an idempotency key; retry never duplicates
    server.down = false;
    s2
      ..offline = false
      ..readOnlyOffline = false;
    expect(await s2.flushCoreOutbox(), isTrue);
    expect(server.buys.length, 1);
    expect(s2.coreOutbox.isEmpty, isTrue);
    expect(s2.pendingWrites, 0);
    s2.notifyListeners();
    expect(s2.openTrades.where((x) => (x.id ?? 0) < 0), isEmpty); // temp row gone
  });
}

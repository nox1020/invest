import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:invest/data/invest_api_client.dart';
import 'package:invest/data/remote_invest_service.dart';
import 'package:invest/data/session_store.dart';
import 'package:invest/domain/models/asset.dart';
import 'package:invest/domain/models/trade.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('asset and trade maps accept whole-number doubles and numeric strings', () {
    final asset = Asset.fromMap({
      'id': 1.0,
      'name': 'طلا',
      'symbol': 'GOLD',
      'quantity': '2.5',
      'avg_buy_price': '1000',
      'current_price': 10,
    });
    expect(asset.id, 1);
    expect(asset.quantity, 2.5);
    expect(asset.avgBuyPrice, 1000);

    final trade = Trade.fromMap({
      'id': 4.0,
      'asset_id': '9',
      'status': 'open',
      'quantity': '1.25',
      'buy_price': '500',
      'buy_date': '2024-01-01',
      'asset_name': 'طلا',
      'asset_symbol': 'GOLD',
    });
    expect(trade.id, 4);
    expect(trade.assetId, 9);
    expect(trade.quantity, 1.25);
    expect(trade.buyPrice, 500);
  });

  test('dashboard, asset list, and settings ignore the casts that aborted refresh',
      () async {
    SharedPreferences.setMockInitialValues({});
    final session = await SessionStore.load();
    final api = InvestApiClient(
      session,
      client: MockClient((request) async {
        final path = request.url.path;
        if (path.endsWith('/dashboard')) {
          return http.Response(
            jsonEncode({
              'success': true,
              'metrics': {
                'total_value': '1500.5',
                'total_pnl': '10',
                'open_count': '2',
                'closed_count': 1.0,
              },
              'gold_fund': null,
              'growth_series': [
                {'date': '2024-01-01', 'value': '10'},
                {'date': '2024-01', 'value': 3},
              ],
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (path.endsWith('/assets')) {
          return http.Response(
            jsonEncode({
              'success': true,
              'items': [
                {'id': 4.0, 'name': 'صندوق', 'quantity': '1.5'},
              ],
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response(
          jsonEncode({'success': true, 'settings': <String, dynamic>{}}),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    final remote = RemoteInvestService(api);

    final dash = await remote.fetchDashboard('gregorian');
    expect(dash.totalValue, 1500.5);
    expect(dash.openCount, 2);
    expect(dash.closedCount, 1);
    expect(dash.goldFund.goldHoldingG, 0);
    expect(dash.growthSeries, hasLength(2));
    expect(dash.growthSeries.first.value, 10);
    expect(dash.growthSeries.last.date, '2024-01');

    final assets = await remote.assets.listAll();
    expect(assets.single.id, 4);
    expect(assets.single.name, 'صندوق');
    expect(assets.single.quantity, 1.5);

    final settings = await remote.fetchSettings();
    expect(settings.settings.calendar, isNotEmpty);
  });

  test('a non-list asset payload and a non-object settings payload do not throw',
      () async {
    SharedPreferences.setMockInitialValues({});
    final session = await SessionStore.load();
    var assetsCall = true;
    final api = InvestApiClient(
      session,
      client: MockClient((request) async {
        if (assetsCall) {
          assetsCall = false;
          return http.Response(
            jsonEncode({'success': true, 'items': {'unexpected': true}}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response(
          jsonEncode({'success': true, 'settings': null}),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    final remote = RemoteInvestService(api);
    expect(await remote.assets.listAll(), isEmpty);
    expect((await remote.fetchSettings()).settings.currency, isNotEmpty);
  });
}

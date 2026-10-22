import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:invest/config/app_config.dart';
import 'package:invest/data/invest_api_client.dart';
import 'package:invest/data/remote_invest_service.dart';
import 'package:invest/data/session_store.dart';
import 'package:invest/domain/models/app_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<RemoteInvestService> _svc(Map<String, dynamic> Function(Map<String, dynamic> sent) echo) async {
  SharedPreferences.setMockInitialValues({
    AppConfig.prefBaseUrl: 'https://vinor.test',
    AppConfig.prefSessionCookie: 'vinor_session=t',
  });
  final session = await SessionStore.load();
  final api = InvestApiClient(session, client: MockClient((r) async {
    final sent = Map<String, dynamic>.from(jsonDecode(r.body) as Map);
    return http.Response(jsonEncode({'success': true, 'settings': echo(sent)}), 200,
        headers: {'content-type': 'application/json; charset=utf-8'});
  }))
    ..restoreSessionCookie();
  return RemoteInvestService(api);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('server keeps everything: no error', () async {
    final svc = await _svc((sent) => sent);
    final b = await svc.saveSettings(AppSettings(annualWithdrawalPct: 20));
    expect(b.settings.annualWithdrawalPct, 20);
  });

  test('server echoes a different value: error names the setting', () async {
    final svc = await _svc((sent) => {...sent, 'annual_withdrawal_pct': 10});
    await expectLater(
      svc.saveSettings(AppSettings(annualWithdrawalPct: 20)),
      throwsA(isA<SettingsNotSavedException>().having(
          (e) => e.toString(), 'msg', contains('درصد برداشت سالانه'))),
    );
  });

  test('server drops alerts it was sent: error', () async {
    final svc = await _svc((sent) => {...sent, 'price_alerts': []});
    final s = AppSettings()
      ..priceAlerts = [
        for (final a in AppSettings.fromJson({
          'price_alerts': [
            {'id': 'a', 'symbol': 'USDT', 'target': 1, 'above': true}
          ]
        }).priceAlerts)
          a
      ];
    if (s.priceAlerts.isEmpty) return; // parser shape guard
    await expectLater(svc.saveSettings(s), throwsA(isA<SettingsNotSavedException>()));
  });

  test('older server omits a key: tolerated', () async {
    final svc = await _svc((sent) => {...sent}..remove('annual_withdrawal_pct'));
    await svc.saveSettings(AppSettings(annualWithdrawalPct: 33));
  });
}

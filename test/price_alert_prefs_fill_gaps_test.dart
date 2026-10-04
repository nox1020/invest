import 'package:flutter_test/flutter_test.dart';
import 'package:invest/domain/models/app_settings.dart';
import 'package:invest/domain/models/price_alert.dart';
import 'package:invest/domain/models/profit_alert.dart';
import 'package:invest/domain/services/price_alert_prefs.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('fillGapsOnto only fills empty server lists', () async {
    final local = AppSettings(
      priceAlerts: [PriceAlert(id: 'usdt', above: 1)],
      profitAlerts: [ProfitAlert(id: 'asset:1', profitPct: 3)],
    );
    await PriceAlertPrefs.saveFrom(local);

    final server = AppSettings(
      priceAlerts: [PriceAlert(id: 'gold', above: 9)],
      profitAlerts: [],
    );
    final changed = await PriceAlertPrefs.fillGapsOnto(server);
    expect(changed, isTrue);
    expect(server.priceAlerts.single.id, 'gold');
    expect(server.profitAlerts.single.id, 'asset:1');
  });

  test('fillGapsOnto is no-op when server already has alerts', () async {
    final local = AppSettings(
      priceAlerts: [PriceAlert(id: 'usdt', above: 1)],
      profitAlerts: [ProfitAlert(id: 'asset:1', profitPct: 3)],
    );
    await PriceAlertPrefs.saveFrom(local);

    final server = AppSettings(
      priceAlerts: [PriceAlert(id: 'gold', above: 9)],
      profitAlerts: [ProfitAlert(id: 'asset:9', profitPct: 1)],
    );
    final changed = await PriceAlertPrefs.fillGapsOnto(server);
    expect(changed, isFalse);
    expect(server.priceAlerts.single.id, 'gold');
    expect(server.profitAlerts.single.id, 'asset:9');
  });
}

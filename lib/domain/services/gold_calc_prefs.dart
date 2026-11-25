import 'dart:convert';

import 'package:invest/data/local_platform.dart';
import 'package:invest/domain/services/gold_calc.dart';

/// Device-local memory of the gold calculator: the last product used
/// (first run: آب‌شده / آنلاین), each product's last fees, the input mode
/// and the lot order.
class GoldCalcPrefs {
  const GoldCalcPrefs({
    this.product = GoldProduct.online,
    this.onlineFees = GoldFees.onlineDefault,
    this.jewelryFees = GoldFees.jewelryDefault,
    this.buyMode = GoldInputMode.amount,
    this.sellMode = GoldInputMode.weight,
    this.lotOrder = GoldLotOrder.fifo,
  });

  static const prefsKey = 'vplus_gold_calc_prefs_v1';

  final GoldProduct product;
  final GoldFees onlineFees;
  final GoldFees jewelryFees;
  final GoldInputMode buyMode;
  final GoldInputMode sellMode;
  final GoldLotOrder lotOrder;

  GoldFees feesFor(GoldProduct p) => p == GoldProduct.online ? onlineFees : jewelryFees;

  GoldCalcPrefs copyWith({
    GoldProduct? product,
    GoldFees? onlineFees,
    GoldFees? jewelryFees,
    GoldInputMode? buyMode,
    GoldInputMode? sellMode,
    GoldLotOrder? lotOrder,
  }) =>
      GoldCalcPrefs(
        product: product ?? this.product,
        onlineFees: onlineFees ?? this.onlineFees,
        jewelryFees: jewelryFees ?? this.jewelryFees,
        buyMode: buyMode ?? this.buyMode,
        sellMode: sellMode ?? this.sellMode,
        lotOrder: lotOrder ?? this.lotOrder,
      );

  Map<String, dynamic> toJson() => {
        'product': product.id,
        'online': onlineFees.toJson(),
        'jewelry': jewelryFees.toJson(),
        'buy_mode': buyMode.name,
        'sell_mode': sellMode.name,
        'lot_order': lotOrder.name,
      };

  static GoldInputMode _mode(Object? v, GoldInputMode d) =>
      GoldInputMode.values.firstWhere((e) => e.name == '$v', orElse: () => d);

  static GoldCalcPrefs fromJson(Object? raw) {
    if (raw is! Map) return const GoldCalcPrefs();
    return GoldCalcPrefs(
      product: GoldProductX.parse(raw['product']),
      onlineFees: GoldFees.fromJson(raw['online'], GoldFees.onlineDefault),
      jewelryFees: GoldFees.fromJson(raw['jewelry'], GoldFees.jewelryDefault),
      buyMode: _mode(raw['buy_mode'], GoldInputMode.amount),
      sellMode: _mode(raw['sell_mode'], GoldInputMode.weight),
      lotOrder: GoldLotOrderX.parse(raw['lot_order']),
    );
  }

  static GoldCalcPrefs decode(String? raw) {
    if (raw == null || raw.trim().isEmpty) return const GoldCalcPrefs();
    try {
      return fromJson(jsonDecode(raw));
    } catch (_) {
      return const GoldCalcPrefs();
    }
  }

  static Future<GoldCalcPrefs> load() async {
    final prefs = await LocalPrefs.open();
    if (prefs == null) return const GoldCalcPrefs();
    return decode(prefs.getString(prefsKey));
  }

  Future<void> save() async {
    final prefs = await LocalPrefs.open();
    if (prefs == null) return;
    await LocalPrefs.setString(prefs, prefsKey, jsonEncode(toJson()));
  }
}

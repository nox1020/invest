import 'package:invest/domain/models/trade.dart';
import 'package:invest/state/app_state.dart';
import 'package:invest/ui/gold/gold_format.dart';

/// Warning for deleting trades recorded from «صندوق طلا»: their cash rows
/// go with them, so the fund cash changes. Null when none is tagged.
String? goldFundDeleteNote(AppState state, Iterable<Trade> trades) {
  final tagged = [
    for (final t in trades)
      if (t.buyFromGoldFund || t.soldToGoldFund) t
  ];
  if (tagged.isEmpty) return null;
  final book = state.goldFund;
  final effect = tagged.fold<double>(0, (s, t) => s + book.cashEffectOf(t));
  final before = book.cash;
  final after = before - effect;
  if (effect.abs() < 0.5) {
    return 'این معامله از «صندوق طلا» ثبت شده و ردیفش از گردش نقد صندوق هم حذف می‌شود.';
  }
  return 'این معامله از «صندوق طلا» ثبت شده؛ با حذفش ردیف نقد آن هم حذف می‌شود و نقد صندوق از ${gToman(before)} به ${gToman(after)} تومان می‌رسد.';
}

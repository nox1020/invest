import 'package:invest/domain/services/gold_price_log.dart';

/// Where today's price stands against yesterday's.
enum GoldColumnDirection { up, down, flat }

/// «ستون قیمت طلا»: one vertical column from the period low (bottom) to the
/// period high (top), a marker at the current price and a faint mark at the
/// previous day's price. Pure Dart; the widget only draws it.
class GoldColumnModel {
  const GoldColumnModel({
    required this.days,
    required this.price,
    required this.low,
    required this.high,
    required this.reference,
    required this.referenceDaysAgo,
    required this.daysWithData,
    this.average,
  });

  /// Fewer days than this: no average (too few to mean anything).
  static const minDaysForAverage = 3;

  /// Below this relative move (0.01%) the day counts as flat.
  static const flatEpsilon = 1e-4;

  /// Fewer distinct days than this: the range is not shown yet.
  static const minDaysForRange = 2;

  /// Period length (days back from today, today included).
  final int days;

  /// Current 18k Toman/gram; null when there is no price at all.
  final double? price;

  /// Period low/high, the current price and [reference] included, so the
  /// marker never leaves the column. Null without a price.
  final double? low;
  final double? high;

  /// Previous day's price (latest logged day before today, else derived
  /// from the 24h change). Null when unknown.
  final double? reference;

  /// How many days before the price's day [reference] is (1 = yesterday,
  /// more after a market holiday or a day without a log); 1 when it
  /// comes from the 24h change; null without a reference.
  final int? referenceDaysAgo;

  /// Distinct days with a price inside the period (today counts when there
  /// is a current price).
  final int daysWithData;

  /// Mean of one price per day over the period (today = the current
  /// price). Null below [minDaysForAverage] days.
  final double? average;

  bool get hasPrice => price != null;

  double? get averagePosition => hasRange ? fractionOf(average) : null;

  /// Current price is under the period average (by more than
  /// [flatEpsilon]); false without an average.
  bool get belowAverage {
    final a = average, p = price;
    if (a == null || p == null || a <= 0) return false;
    return (a - p) / a > flatEpsilon;
  }

  /// How far under the average, Toman (positive) / percent of the average.
  double? get belowAverageGap => belowAverage ? average! - price! : null;
  double? get belowAveragePct => belowAverage ? (average! - price!) / average! * 100 : null;

  /// Low/high are meaningful (at least [minDaysForRange] days of data).
  bool get hasRange => hasPrice && daysWithData >= minDaysForRange;

  /// Low and high are the same price.
  bool get flatRange => hasRange && (high! - low!).abs() < 0.5;

  /// 0 = bottom (low), 1 = top (high), clamped; 0.5 on a flat range.
  double? fractionOf(double? v) {
    if (v == null || !v.isFinite || low == null || high == null) return null;
    final span = high! - low!;
    if (span.abs() < 0.5) return 0.5;
    final f = (v - low!) / span;
    return f < 0 ? 0.0 : (f > 1 ? 1.0 : f);
  }

  double? get position => hasRange ? fractionOf(price) : null;
  double? get referencePosition => hasRange ? fractionOf(reference) : null;

  /// Toman change since [reference].
  double? get change => price == null || reference == null ? null : price! - reference!;

  /// Percent change since [reference].
  double? get changePct => change == null || reference! <= 0 ? null : change! / reference! * 100;

  GoldColumnDirection? get direction {
    final c = change;
    if (c == null) return null;
    if (reference! <= 0 || (c / reference!).abs() < flatEpsilon) return GoldColumnDirection.flat;
    return c > 0 ? GoldColumnDirection.up : GoldColumnDirection.down;
  }

  static double? _ok(double? v) => v != null && v.isFinite && v > 0 ? v : null;

  /// Builds the column from the daily log and the current price.
  ///
  /// [today] is the Tehran `YYYY-MM-DD` (`tehranTodayIso()`); log days
  /// after it are ignored. With no [current] price, today's or the latest
  /// logged price in the period stands in. [change24hPct] is only used for
  /// the reference when no earlier day is logged.
  static GoldColumnModel compute({
    required List<GoldPricePoint> log,
    required String today,
    double? current,
    double? change24hPct,
    int days = 30,
  }) {
    final t = _day(today);
    final inWindow = <GoldPricePoint>[];
    if (t != null) {
      for (final p in log) {
        final d = _day(p.date);
        if (d == null || _ok(p.mid) == null) continue;
        final ago = t.difference(d).inDays;
        if (ago >= 0 && ago < days) inWindow.add(p);
      }
    }
    inWindow.sort((a, b) => a.date.compareTo(b.date));

    var price = _ok(current);
    var priceDate = today;
    if (price == null && inWindow.isNotEmpty) {
      price = inWindow.last.mid;
      priceDate = inWindow.last.date;
    }
    if (price == null) {
      return GoldColumnModel(
        days: days,
        price: null,
        low: null,
        high: null,
        reference: null,
        referenceDaysAgo: null,
        daysWithData: inWindow.map((p) => p.date).toSet().length,
      );
    }

    // Previous day: the latest logged day strictly before the price's day.
    double? reference;
    int? refAgo;
    for (final p in inWindow.reversed) {
      if (p.date.compareTo(priceDate) < 0) {
        reference = p.mid;
        refAgo = _day(priceDate)!.difference(_day(p.date)!).inDays;
        break;
      }
    }
    final ch = change24hPct;
    if (reference == null && ch != null && ch.isFinite && ch > -100) {
      reference = _ok(price / (1 + ch / 100));
      if (reference != null) refAgo = 1;
    }

    final dates = {for (final p in inWindow) p.date, priceDate};
    // One price per day; the current price stands for its own day.
    final perDay = <String, double>{for (final p in inWindow) p.date: p.mid, priceDate: price};
    final average = perDay.length >= minDaysForAverage
        ? perDay.values.fold<double>(0, (a, b) => a + b) / perDay.length
        : null;
    var lo = price, hi = price;
    for (final p in inWindow) {
      if (p.mid < lo) lo = p.mid;
      if (p.mid > hi) hi = p.mid;
    }
    if (reference != null) {
      if (reference < lo) lo = reference;
      if (reference > hi) hi = reference;
    }
    return GoldColumnModel(
      days: days,
      price: price,
      low: lo,
      high: hi,
      reference: reference,
      referenceDaysAgo: refAgo,
      daysWithData: dates.length,
      average: average,
    );
  }

  static DateTime? _day(String iso) {
    final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(iso);
    if (m == null) return null;
    return DateTime.utc(int.parse(m.group(1)!), int.parse(m.group(2)!), int.parse(m.group(3)!));
  }
}

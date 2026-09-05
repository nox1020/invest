import 'package:invest/config/app_config.dart';
import 'package:invest/data/repositories.dart';
import 'package:invest/domain/models/metrics.dart';
import 'package:invest/domain/services/trade_service.dart';
import 'package:invest/domain/utils/dates.dart';
import 'package:sqflite/sqflite.dart';

class PortfolioService {
  PortfolioService(this._db)
      : assets = AssetRepository(_db),
        trades = TradeRepository(_db),
        tradeService = TradeService(_db);

  final Database _db;
  final AssetRepository assets;
  final TradeRepository trades;
  final TradeService tradeService;

  Future<DashboardMetrics> getMetrics({String calendar = AppConfig.calendarJalali}) async {
    final allAssets = await assets.listAll();
    final totalValue =
        allAssets.fold<double>(0, (s, a) => s + a.totalValue);
    final totalCost =
        allAssets.fold<double>(0, (s, a) => s + a.costBasis);
    final unrealized = totalValue - totalCost;
    final stats = await trades.closedStats();
    final realized = stats['total_pnl'] ?? 0;
    final totalPnl = unrealized + realized;
    final totalPnlPct =
        totalCost > 0 ? (totalValue - totalCost) / totalCost * 100 : 0.0;

    final yearKey = yearPeriodKey(todayIso(), calendar);
    var yearRealized = 0.0;
    for (final t in await trades.listClosed()) {
      if (t.sellDate == null || t.realizedPnl == null) continue;
      if (yearPeriodKey(t.sellDate!, calendar) == yearKey) {
        yearRealized += t.realizedPnl!;
      }
    }

    final gold = await tradeService.goldFundMetrics();
    final growth = await loadGrowthSeries(totalValue);
    return DashboardMetrics(
      totalValue: totalValue,
      totalPnl: totalPnl,
      totalPnlPct: totalPnlPct,
      realizedPnl: realized,
      unrealizedPnl: unrealized,
      openCount: await trades.countByStatus(AppConfig.tradeOpen),
      closedCount: await trades.countByStatus(AppConfig.tradeClosed),
      yearRealizedPnl: yearRealized,
      yearKey: yearKey,
      goldFund: gold,
      growthSeries: growth,
    );
  }

  Future<List<SeriesPoint>> loadGrowthSeries(double todayValue) async {
    final today = todayIso();
    final rows = await _db.query('capital_snapshots', orderBy: 'date ASC');
    final points = <SeriesPoint>[];
    for (final row in rows) {
      final date = (row['date'] as String?) ?? '';
      if (date.isEmpty || date == today) continue;
      points.add(
        SeriesPoint(
          date: date.length >= 10 ? date.substring(0, 10) : date,
          value: (row['total_value'] as num?)?.toDouble() ?? 0,
        ),
      );
    }
    points.add(SeriesPoint(date: today, value: todayValue));
    return points;
  }

  Future<void> recordSnapshot() async {
    final value =
        (await assets.listAll()).fold<double>(0, (s, a) => s + a.totalValue);
    final date = todayIso();
    await _db.insert(
      'capital_snapshots',
      {
        'date': date,
        'total_value': value,
        'created_at': nowIso(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}

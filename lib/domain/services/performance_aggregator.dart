import 'package:invest/data/biz_store.dart';
import 'package:invest/data/projects_store.dart';
import 'package:invest/domain/models/asset.dart';
import 'package:invest/domain/models/asset_kind.dart';
import 'package:invest/domain/models/trade.dart';
import 'package:invest/domain/utils/biz_dates.dart';
import 'package:invest/domain/utils/dates.dart';
import 'package:shamsi_date/shamsi_date.dart';

/// Every business or asset field tracked inside the unified Performance page.
enum PerfDomain {
  office,
  property,
  gold,
  cash,
  crypto,
  stock,
  vehicle,
  projects,
  other,
}

extension PerfDomainX on PerfDomain {
  String get id => name;

  String get label => switch (this) {
        PerfDomain.office => 'عملیات دفتر',
        PerfDomain.property => 'ملک و مستغلات',
        PerfDomain.gold => 'طلا و سکه',
        PerfDomain.cash => 'ارز و نقد',
        PerfDomain.crypto => 'ارز دیجیتال',
        PerfDomain.stock => 'سهام و صندوق',
        PerfDomain.vehicle => 'خودرو',
        PerfDomain.projects => 'پیمانکاری',
        PerfDomain.other => 'سایر زمینه‌ها',
      };

  String get shortLabel => switch (this) {
        PerfDomain.office => 'دفتر',
        PerfDomain.property => 'ملک',
        PerfDomain.gold => 'طلا',
        PerfDomain.cash => 'ارز',
        PerfDomain.crypto => 'رمزارز',
        PerfDomain.stock => 'بورس',
        PerfDomain.vehicle => 'خودرو',
        PerfDomain.projects => 'پروژه',
        PerfDomain.other => 'سایر',
      };

  bool get isOffice => this == PerfDomain.office;
}

PerfDomain perfDomainFromAssetKind(AssetKind kind) => switch (kind) {
      AssetKind.property => PerfDomain.property,
      AssetKind.gold => PerfDomain.gold,
      AssetKind.cash => PerfDomain.cash,
      AssetKind.crypto => PerfDomain.crypto,
      AssetKind.stock => PerfDomain.stock,
      AssetKind.vehicle => PerfDomain.vehicle,
      AssetKind.other => PerfDomain.other,
    };

/// Parses a Jalali (`YYYY/MM/DD`, `D/M/YYYY`) or Gregorian ISO (`YYYY-MM-DD`)
/// date string into its Jalali `(year, month)` pair, or `null` when invalid.
String _safeDateLabel(String? raw) {
  final t = raw?.trim() ?? '';
  if (t.isEmpty) return '';
  try {
    return formatFlexibleDisplayDate(t, 'jalali');
  } catch (_) {
    return t;
  }
}

({int year, int month})? perfJalaliMonthOf(String? raw) {
  final text = raw?.trim() ?? '';
  if (text.isEmpty) return null;

  final j = parseBizDate(text);
  if (j != null) return (year: j.year, month: j.month);

  final iso = tryNormalizeToIso(text);
  if (iso != null) {
    final dt = DateTime.tryParse(iso);
    if (dt != null) {
      final gj = Jalali.fromDateTime(dt);
      return (year: gj.year, month: gj.month);
    }
  }
  return null;
}

/// Auditable deal entry attached to a Jalali month inside Performance.
class PerfDealItem {
  const PerfDealItem({
    required this.domain,
    required this.title,
    required this.isSold,
    required this.buyAmount,
    required this.sellAmount,
    required this.profit,
    required this.dateLabel,
    this.subtitle = '',
  });

  final PerfDomain domain;
  final String title;
  final bool isSold;
  final double buyAmount;
  final double sellAmount;
  final double? profit;
  final String dateLabel;
  final String subtitle;
}

/// Aggregated annual metrics for one [PerfDomain] + live open exposure.
class PerfDomainSummary {
  const PerfDomainSummary({
    required this.domain,
    this.net = 0,
    this.revenue = 0,
    this.soldCount = 0,
    this.soldAmount = 0,
    this.boughtCount = 0,
    this.boughtAmount = 0,
    this.openCount = 0,
    this.openInvested = 0,
    this.openCurrentValue = 0,
    this.openUnrealizedPnl = 0,
  });

  final PerfDomain domain;
  final double net;
  final double revenue;
  final int soldCount;
  final double soldAmount;
  final int boughtCount;
  final double boughtAmount;
  final int openCount;
  final double openInvested;
  final double openCurrentValue;
  final double openUnrealizedPnl;

  bool get hasActivity =>
      net != 0 ||
      revenue != 0 ||
      soldCount > 0 ||
      boughtCount > 0 ||
      openCount > 0;
}

/// Monthly row combining office ops (if present) and all deals in any field.
class PerfMonthSummary {
  PerfMonthSummary({
    required this.year,
    required this.month,
    this.bizMonth,
    required Map<PerfDomain, double> profitByDomain,
    required Map<PerfDomain, int> soldCountByDomain,
    required Map<PerfDomain, double> soldAmountByDomain,
    required Map<PerfDomain, int> boughtCountByDomain,
    required Map<PerfDomain, double> boughtAmountByDomain,
    required List<PerfDealItem> deals,
  })  : profitByDomain = Map.unmodifiable(profitByDomain),
        soldCountByDomain = Map.unmodifiable(soldCountByDomain),
        soldAmountByDomain = Map.unmodifiable(soldAmountByDomain),
        boughtCountByDomain = Map.unmodifiable(boughtCountByDomain),
        boughtAmountByDomain = Map.unmodifiable(boughtAmountByDomain),
        deals = List.unmodifiable(deals);

  final int year;
  final int month;
  final BizMonth? bizMonth;
  final Map<PerfDomain, double> profitByDomain;
  final Map<PerfDomain, int> soldCountByDomain;
  final Map<PerfDomain, double> soldAmountByDomain;
  final Map<PerfDomain, int> boughtCountByDomain;
  final Map<PerfDomain, double> boughtAmountByDomain;
  final List<PerfDealItem> deals;

  bool _includes(PerfDomain d, Set<PerfDomain> filter) =>
      filter.isEmpty || filter.contains(d);

  bool includesOffice(Set<PerfDomain> filter) =>
      _includes(PerfDomain.office, filter);

  double get staff => bizMonth?.staff ?? 0;
  double get pwo => bizMonth?.pwo ?? 0;
  double get ads => bizMonth?.ads ?? 0;
  double get income => bizMonth?.income ?? 0;
  double get incomeEffective => bizMonth?.incomeEffective ?? 0;
  bool get incomeDupTrades => bizMonth?.incomeDupTrades ?? false;
  bool get hasOps => bizMonth?.hasOps ?? false;
  String get note => bizMonth?.note ?? '';

  double get officeNet => incomeEffective - staff - pwo - ads;

  double netFor(Set<PerfDomain> filter) {
    var total = 0.0;
    for (final entry in profitByDomain.entries) {
      if (_includes(entry.key, filter)) {
        total += entry.value;
      }
    }
    return total;
  }

  double tradeProfitFor(Set<PerfDomain> filter) {
    var total = 0.0;
    for (final entry in profitByDomain.entries) {
      if (entry.key == PerfDomain.office) continue;
      if (_includes(entry.key, filter)) {
        total += entry.value;
      }
    }
    return total;
  }

  int soldCountFor(Set<PerfDomain> filter) {
    var total = 0;
    for (final entry in soldCountByDomain.entries) {
      if (entry.key == PerfDomain.office) continue;
      if (_includes(entry.key, filter)) {
        total += entry.value;
      }
    }
    return total;
  }

  int boughtCountFor(Set<PerfDomain> filter) {
    var total = 0;
    for (final entry in boughtCountByDomain.entries) {
      if (_includes(entry.key, filter)) {
        total += entry.value;
      }
    }
    return total;
  }

  double boughtAmountFor(Set<PerfDomain> filter) {
    var total = 0.0;
    for (final entry in boughtAmountByDomain.entries) {
      if (_includes(entry.key, filter)) {
        total += entry.value;
      }
    }
    return total;
  }

  bool hasOfficeActivityFor(Set<PerfDomain> filter) =>
      includesOffice(filter) &&
      (hasOps || pwo != 0 || staff != 0 || ads != 0 || income != 0);

  bool isEmptyFor(Set<PerfDomain> filter) {
    if (hasOfficeActivityFor(filter)) return false;
    for (final d in profitByDomain.keys) {
      if (_includes(d, filter) && profitByDomain[d] != 0) return false;
    }
    if (soldCountFor(filter) > 0 || boughtCountFor(filter) > 0) return false;
    return true;
  }

  List<PerfDealItem> dealsFor(Set<PerfDomain> filter) {
    if (filter.isEmpty) return deals;
    return [
      for (final item in deals)
        if (filter.contains(item.domain)) item,
    ];
  }

  /// Active non-office domains that contributed realized or bought activity in this month.
  List<PerfDomain> activeDealDomainsFor(Set<PerfDomain> filter) {
    final active = <PerfDomain>[];
    for (final d in PerfDomain.values) {
      if (d == PerfDomain.office) continue;
      if (!_includes(d, filter)) continue;
      final p = profitByDomain[d] ?? 0;
      final s = soldCountByDomain[d] ?? 0;
      final b = boughtCountByDomain[d] ?? 0;
      if (p != 0 || s > 0 || b > 0) {
        active.add(d);
      }
    }
    return active;
  }
}

/// Unified annual view of all performance sources for a Jalali year.
class PerfYearSummary {
  const PerfYearSummary({
    required this.year,
    required this.months,
    required this.byDomain,
    required this.activeDomains,
    required this.openDomains,
    required this.totalOpenCount,
    required this.totalOpenInvested,
    required this.totalOpenCurrentValue,
    required this.totalOpenUnrealizedPnl,
    required this.hasOfficeData,
    required this.hasAnyDealData,
  });

  final int year;
  final List<PerfMonthSummary> months;
  final Map<PerfDomain, PerfDomainSummary> byDomain;
  final List<PerfDomain> activeDomains;
  final List<PerfDomainSummary> openDomains;
  final int totalOpenCount;
  final double totalOpenInvested;
  final double totalOpenCurrentValue;
  final double totalOpenUnrealizedPnl;
  final bool hasOfficeData;
  final bool hasAnyDealData;

  bool get hasAnyOpen => totalOpenCount > 0;
  bool get hasAnyYearData =>
      hasOfficeData ||
      hasAnyDealData ||
      months.any((m) => !m.isEmptyFor(const {}));

  bool _includes(PerfDomain d, Set<PerfDomain> filter) =>
      filter.isEmpty || filter.contains(d);

  bool includesOffice(Set<PerfDomain> filter) =>
      _includes(PerfDomain.office, filter);

  List<PerfMonthSummary> activeMonthsFor(Set<PerfDomain> filter) => [
        for (final m in months)
          if (!m.isEmptyFor(filter)) m,
      ];

  double totalNetFor(Set<PerfDomain> filter) =>
      months.fold<double>(0, (s, m) => s + m.netFor(filter));

  double totalTradeProfitFor(Set<PerfDomain> filter) =>
      months.fold<double>(0, (s, m) => s + m.tradeProfitFor(filter));

  double totalIncomeEffectiveFor(Set<PerfDomain> filter) {
    if (!includesOffice(filter)) return 0;
    return months.fold<double>(0, (s, m) => s + m.incomeEffective);
  }

  double totalStaffFor(Set<PerfDomain> filter) {
    if (!includesOffice(filter)) return 0;
    return months.fold<double>(0, (s, m) => s + m.staff);
  }

  double totalPwoFor(Set<PerfDomain> filter) {
    if (!includesOffice(filter)) return 0;
    return months.fold<double>(0, (s, m) => s + m.pwo);
  }

  double totalAdsFor(Set<PerfDomain> filter) {
    if (!includesOffice(filter)) return 0;
    return months.fold<double>(0, (s, m) => s + m.ads);
  }

  int totalSoldCountFor(Set<PerfDomain> filter) =>
      months.fold<int>(0, (s, m) => s + m.soldCountFor(filter));

  int totalBoughtCountFor(Set<PerfDomain> filter) =>
      months.fold<int>(0, (s, m) => s + m.boughtCountFor(filter));

  double totalBoughtAmountFor(Set<PerfDomain> filter) =>
      months.fold<double>(0, (s, m) => s + m.boughtAmountFor(filter));

  double avgNetFor(Set<PerfDomain> filter) {
    final active = activeMonthsFor(filter);
    if (active.isEmpty) return 0;
    return totalNetFor(filter) / active.length;
  }

  double? marginPctFor(Set<PerfDomain> filter) {
    final rev = totalIncomeEffectiveFor(filter) + totalTradeProfitFor(filter);
    if (rev <= 0) return null;
    return totalNetFor(filter) / rev * 100;
  }

  int mismatchCountFor(Set<PerfDomain> filter) {
    if (!includesOffice(filter)) return 0;
    return months.where((m) => m.incomeDupTrades).length;
  }
}

class _MonthAcc {
  BizMonth? bizMonth;
  final Map<PerfDomain, double> profit = {};
  final Map<PerfDomain, int> soldCount = {};
  final Map<PerfDomain, double> soldAmount = {};
  final Map<PerfDomain, int> boughtCount = {};
  final Map<PerfDomain, double> boughtAmount = {};
  final List<PerfDealItem> deals = [];

  void addSold({
    required PerfDomain domain,
    required double profitVal,
    required double sellAmount,
    required PerfDealItem item,
  }) {
    profit[domain] = (profit[domain] ?? 0) + profitVal;
    soldCount[domain] = (soldCount[domain] ?? 0) + 1;
    soldAmount[domain] = (soldAmount[domain] ?? 0) + sellAmount;
    deals.add(item);
  }

  void addBought({
    required PerfDomain domain,
    required double buyAmount,
    PerfDealItem? item,
  }) {
    boughtCount[domain] = (boughtCount[domain] ?? 0) + 1;
    boughtAmount[domain] = (boughtAmount[domain] ?? 0) + buyAmount;
    if (item != null) deals.add(item);
  }
}

class _DomainAcc {
  double net = 0;
  double revenue = 0;
  int soldCount = 0;
  double soldAmount = 0;
  int boughtCount = 0;
  double boughtAmount = 0;
  int openCount = 0;
  double openInvested = 0;
  double openCurrentValue = 0;
  double openUnrealizedPnl = 0;
}

class PerformanceAggregator {
  static PerfDomain resolveTradeDomain(Trade trade, Map<int, Asset> assetsById) {
    final asset = assetsById[trade.assetId];
    final kind = asset != null
        ? detectAssetKind(
            name: asset.name,
            symbol: asset.symbol,
            notes: asset.notes,
          )
        : detectAssetKind(
            name: trade.assetName,
            symbol: trade.assetSymbol,
          );
    return perfDomainFromAssetKind(kind);
  }

  static double realizedProfitOfTrade(Trade t) {
    if (t.realizedPnl != null) return t.realizedPnl!;
    final sell = t.sellPrice ?? t.currentPrice;
    return t.quantity * (sell - t.buyPrice) - t.buyFee - t.sellFee;
  }

  static PerfYearSummary build({
    required int year,
    BizSnapshot? biz,
    Iterable<Asset> assets = const [],
    Iterable<Trade> openTrades = const [],
    Iterable<Trade> closedTrades = const [],
    Iterable<Project> projects = const [],
    bool useBizMonthsForYear = true,
  }) {
    final assetsById = <int, Asset>{
      for (final a in assets)
        if (a.id != null) a.id!: a,
    };

    final monthsAcc = <int, _MonthAcc>{
      for (var m = 1; m <= 12; m++) m: _MonthAcc(),
    };
    final domAcc = <PerfDomain, _DomainAcc>{
      for (final d in PerfDomain.values) d: _DomainAcc(),
    };

    var hasOfficeData = false;
    var hasAnyDealData = false;

    // 1. Office monthly ops (when BizSnapshot matches the requested year)
    final bizSnap = biz ?? BizSnapshot.empty;
    if (useBizMonthsForYear && bizSnap.months.isNotEmpty) {
      for (final bm in bizSnap.months) {
        if (bm.year != year || bm.month < 1 || bm.month > 12) continue;
        final ma = monthsAcc[bm.month]!;
        ma.bizMonth = bm;
        final officeNet = bm.incomeEffective - bm.staff - bm.pwo - bm.ads;
        ma.profit[PerfDomain.office] = officeNet;
        domAcc[PerfDomain.office]!.net += officeNet;
        domAcc[PerfDomain.office]!.revenue += bm.incomeEffective;
        if (bm.hasOps || bm.pwo != 0 || bm.staff != 0 || bm.ads != 0 || bm.income != 0) {
          hasOfficeData = true;
        }
      }
    }

    // 2. Real estate & office deals from BizStore
    for (final pt in bizSnap.trades) {
      final buyM = perfJalaliMonthOf(pt.buyDate);
      final sellM = pt.sold ? perfJalaliMonthOf(pt.sellDate) : null;
      final title = pt.title.trim().isEmpty ? 'معامله ملک' : pt.title.trim();

      if (buyM != null && buyM.year == year && buyM.month >= 1 && buyM.month <= 12) {
        hasAnyDealData = true;
        // Only add separate deal item if it isn't also sold in the exact same month
        // (avoids listing the same property twice inside a single month's sheet).
        final sameMonthSold = sellM != null && sellM.year == year && sellM.month == buyM.month;
        monthsAcc[buyM.month]!.addBought(
          domain: PerfDomain.property,
          buyAmount: pt.buyAmount,
          item: sameMonthSold
              ? null
              : PerfDealItem(
                  domain: PerfDomain.property,
                  title: title,
                  isSold: false,
                  buyAmount: pt.buyAmount,
                  sellAmount: 0,
                  profit: null,
                  dateLabel: pt.buyDate,
                  subtitle: pt.note,
                ),
        );
        domAcc[PerfDomain.property]!.boughtCount++;
        domAcc[PerfDomain.property]!.boughtAmount += pt.buyAmount;
      }

      if (pt.sold && sellM != null && sellM.year == year && sellM.month >= 1 && sellM.month <= 12) {
        hasAnyDealData = true;
        final p = pt.profit ?? (pt.sellAmount - pt.buyAmount - pt.extraCost);
        monthsAcc[sellM.month]!.addSold(
          domain: PerfDomain.property,
          profitVal: p,
          sellAmount: pt.sellAmount,
          item: PerfDealItem(
            domain: PerfDomain.property,
            title: title,
            isSold: true,
            buyAmount: pt.buyAmount + pt.extraCost,
            sellAmount: pt.sellAmount,
            profit: p,
            dateLabel: pt.sellDate,
            subtitle: pt.note,
          ),
        );
        final da = domAcc[PerfDomain.property]!;
        da.net += p;
        da.revenue += p;
        da.soldCount++;
        da.soldAmount += pt.sellAmount;
      }

      if (!pt.sold) {
        final da = domAcc[PerfDomain.property]!;
        da.openCount++;
        da.openInvested += pt.buyAmount;
        da.openCurrentValue += pt.buyAmount;
      }
    }

    // 3. Closed portfolio/asset trades (gold, cash/USDT, crypto, stock, property, vehicle, other)
    for (final t in closedTrades) {
      final dom = resolveTradeDomain(t, assetsById);
      final asset = assetsById[t.assetId];
      final title = t.assetName.trim().isNotEmpty
          ? t.assetName.trim()
          : (asset?.name.trim().isNotEmpty == true ? asset!.name.trim() : dom.label);
      final buyM = perfJalaliMonthOf(t.buyDate);
      final sellM = perfJalaliMonthOf(t.sellDate) ?? buyM;
      final buyCost = t.buyCost;
      final sellProceeds = t.quantity * (t.sellPrice ?? t.markPrice) - t.sellFee;
      final p = realizedProfitOfTrade(t);

      if (buyM != null && buyM.year == year && buyM.month >= 1 && buyM.month <= 12) {
        hasAnyDealData = true;
        final sameMonthSold = sellM != null && sellM.year == year && sellM.month == buyM.month;
        monthsAcc[buyM.month]!.addBought(
          domain: dom,
          buyAmount: buyCost,
          item: sameMonthSold
              ? null
              : PerfDealItem(
                  domain: dom,
                  title: title,
                  isSold: false,
                  buyAmount: buyCost,
                  sellAmount: 0,
                  profit: null,
                  dateLabel: _safeDateLabel(t.buyDate),
                  subtitle: t.buyNoteDisplay,
                ),
        );
        domAcc[dom]!.boughtCount++;
        domAcc[dom]!.boughtAmount += buyCost;
      }

      if (sellM != null && sellM.year == year && sellM.month >= 1 && sellM.month <= 12) {
        hasAnyDealData = true;
        monthsAcc[sellM.month]!.addSold(
          domain: dom,
          profitVal: p,
          sellAmount: sellProceeds,
          item: PerfDealItem(
            domain: dom,
            title: title,
            isSold: true,
            buyAmount: buyCost,
            sellAmount: sellProceeds,
            profit: p,
            dateLabel: _safeDateLabel((t.sellDate ?? '').trim().isNotEmpty ? t.sellDate : t.buyDate),
            subtitle: t.sellNoteDisplay,
          ),
        );
        final da = domAcc[dom]!;
        da.net += p;
        da.revenue += p;
        da.soldCount++;
        da.soldAmount += sellProceeds;
      }
    }

    // 4. Open portfolio/asset trades -> buy activity in buy month + Open Exposure
    for (final t in openTrades) {
      if (t.quantity <= 1e-9) continue;
      final dom = resolveTradeDomain(t, assetsById);
      final asset = assetsById[t.assetId];
      final title = t.assetName.trim().isNotEmpty
          ? t.assetName.trim()
          : (asset?.name.trim().isNotEmpty == true ? asset!.name.trim() : dom.label);
      final buyM = perfJalaliMonthOf(t.buyDate);
      final buyCost = t.buyCost;

      if (buyM != null && buyM.year == year && buyM.month >= 1 && buyM.month <= 12) {
        hasAnyDealData = true;
        monthsAcc[buyM.month]!.addBought(
          domain: dom,
          buyAmount: buyCost,
          item: PerfDealItem(
            domain: dom,
            title: title,
            isSold: false,
            buyAmount: buyCost,
            sellAmount: 0,
            profit: null,
            dateLabel: _safeDateLabel(t.buyDate),
            subtitle: t.buyNoteDisplay,
          ),
        );
        domAcc[dom]!.boughtCount++;
        domAcc[dom]!.boughtAmount += buyCost;
      }

      final da = domAcc[dom]!;
      da.openCount++;
      da.openInvested += buyCost;
      da.openCurrentValue += t.currentValue;
      da.openUnrealizedPnl += t.unrealizedPnl;
    }

    // 5. Contracting / Investment projects (non-archived)
    for (final p in projects) {
      if (p.archived) continue;
      final title = p.description.trim().isEmpty ? 'پروژه پیمانکاری' : p.description.trim();
      final startM = perfJalaliMonthOf(p.startDate);
      final endM = perfJalaliMonthOf(p.endDate) ?? startM;

      if (p.cost > 0 && startM != null && startM.year == year && startM.month >= 1 && startM.month <= 12) {
        hasAnyDealData = true;
        final sameMonthDone = p.status == ProjectStatus.finished &&
            endM != null &&
            endM.year == year &&
            endM.month == startM.month;
        monthsAcc[startM.month]!.addBought(
          domain: PerfDomain.projects,
          buyAmount: p.cost,
          item: sameMonthDone
              ? null
              : PerfDealItem(
                  domain: PerfDomain.projects,
                  title: title,
                  isSold: false,
                  buyAmount: p.cost,
                  sellAmount: p.contract,
                  profit: null,
                  dateLabel: p.startDate,
                  subtitle: p.note,
                ),
        );
        domAcc[PerfDomain.projects]!.boughtCount++;
        domAcc[PerfDomain.projects]!.boughtAmount += p.cost;
      }

      if (p.status == ProjectStatus.finished) {
        if (endM != null && endM.year == year && endM.month >= 1 && endM.month <= 12) {
          hasAnyDealData = true;
          final profitVal = p.profit ?? (p.contract > 0 ? p.contract - p.cost : 0.0);
          monthsAcc[endM.month]!.addSold(
            domain: PerfDomain.projects,
            profitVal: profitVal,
            sellAmount: p.contract,
            item: PerfDealItem(
              domain: PerfDomain.projects,
              title: title,
              isSold: true,
              buyAmount: p.cost,
              sellAmount: p.contract,
              profit: profitVal,
              dateLabel: p.endDate.trim().isNotEmpty ? p.endDate : p.startDate,
              subtitle: p.note,
            ),
          );
          final da = domAcc[PerfDomain.projects]!;
          da.net += profitVal;
          da.revenue += profitVal;
          da.soldCount++;
          da.soldAmount += p.contract;
        }
      } else {
        // Active or pipeline projects belong in Open / In-Progress Exposure.
        final da = domAcc[PerfDomain.projects]!;
        da.openCount++;
        da.openInvested += p.cost;
        final expectedProfit = p.status == ProjectStatus.active ? (p.profit ?? 0) : 0.0;
        da.openCurrentValue += p.cost + expectedProfit;
        da.openUnrealizedPnl += expectedProfit;
      }
    }

    final months = [
      for (var m = 1; m <= 12; m++)
        PerfMonthSummary(
          year: year,
          month: m,
          bizMonth: monthsAcc[m]!.bizMonth,
          profitByDomain: monthsAcc[m]!.profit,
          soldCountByDomain: monthsAcc[m]!.soldCount,
          soldAmountByDomain: monthsAcc[m]!.soldAmount,
          boughtCountByDomain: monthsAcc[m]!.boughtCount,
          boughtAmountByDomain: monthsAcc[m]!.boughtAmount,
          deals: monthsAcc[m]!.deals,
        ),
    ];

    final byDomain = <PerfDomain, PerfDomainSummary>{
      for (final d in PerfDomain.values)
        d: PerfDomainSummary(
          domain: d,
          net: domAcc[d]!.net,
          revenue: domAcc[d]!.revenue,
          soldCount: domAcc[d]!.soldCount,
          soldAmount: domAcc[d]!.soldAmount,
          boughtCount: domAcc[d]!.boughtCount,
          boughtAmount: domAcc[d]!.boughtAmount,
          openCount: domAcc[d]!.openCount,
          openInvested: domAcc[d]!.openInvested,
          openCurrentValue: domAcc[d]!.openCurrentValue,
          openUnrealizedPnl: domAcc[d]!.openUnrealizedPnl,
        ),
    };

    final activeDomains = [
      for (final d in PerfDomain.values)
        if (byDomain[d]!.hasActivity) d,
    ]..sort((a, b) {
        final sa = byDomain[a]!;
        final sb = byDomain[b]!;
        final cmp = sb.net.abs().compareTo(sa.net.abs());
        if (cmp != 0) return cmp;
        return a.index.compareTo(b.index);
      });

    final openDomains = [
      for (final d in PerfDomain.values)
        if (byDomain[d]!.openCount > 0) byDomain[d]!,
    ]..sort((a, b) => b.openInvested.compareTo(a.openInvested));

    var openCount = 0;
    var openInvested = 0.0;
    var openCurrentValue = 0.0;
    var openUnrealized = 0.0;
    for (final o in openDomains) {
      openCount += o.openCount;
      openInvested += o.openInvested;
      openCurrentValue += o.openCurrentValue;
      openUnrealized += o.openUnrealizedPnl;
    }

    return PerfYearSummary(
      year: year,
      months: months,
      byDomain: byDomain,
      activeDomains: activeDomains,
      openDomains: openDomains,
      totalOpenCount: openCount,
      totalOpenInvested: openInvested,
      totalOpenCurrentValue: openCurrentValue,
      totalOpenUnrealizedPnl: openUnrealized,
      hasOfficeData: hasOfficeData,
      hasAnyDealData: hasAnyDealData,
    );
  }
}

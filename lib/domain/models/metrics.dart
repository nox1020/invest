class GoldFundMetrics {
  const GoldFundMetrics({
    required this.goldInG,
    required this.goldOutG,
    required this.goldHoldingG,
  });

  final double goldInG;
  final double goldOutG;
  final double goldHoldingG;

  double get goldDebtG => goldHoldingG;
}

class DashboardMetrics {
  const DashboardMetrics({
    required this.totalValue,
    required this.totalPnl,
    required this.totalPnlPct,
    required this.realizedPnl,
    required this.unrealizedPnl,
    required this.openCount,
    required this.closedCount,
    required this.yearRealizedPnl,
    required this.yearKey,
    required this.goldFund,
  });

  final double totalValue;
  final double totalPnl;
  final double totalPnlPct;
  final double realizedPnl;
  final double unrealizedPnl;
  final int openCount;
  final int closedCount;
  final double yearRealizedPnl;
  final String yearKey;
  final GoldFundMetrics goldFund;
}

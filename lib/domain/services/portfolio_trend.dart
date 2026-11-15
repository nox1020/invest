import 'package:invest/domain/models/metrics.dart';
import 'package:invest/domain/models/trade.dart';
import 'package:invest/domain/services/dashboard_snapshot.dart';
import 'package:invest/domain/services/portfolio_valuation.dart';
import 'package:invest/domain/utils/dates.dart';

/// The one «روند ۳۰ روز» of the app: like-for-like holdings value (no
/// cheques) over the last 30 days, net of money put in or taken out by
/// buys/sells. The dashboard card and the «ارزش پورتفو» page both call
/// this, so they never show two different trend numbers.
PortfolioTrend portfolioTrend30({
  required DashboardSnapshot snap,
  required List<SeriesPoint> growthSeries,
  Iterable<Trade> openTrades = const [],
  Iterable<Trade> closedTrades = const [],
  String? today,
}) =>
    PortfolioTrend.window(
      series: growthSeries,
      todayValue: snap.holdingsValue,
      today: today ?? todayIso(),
      openTrades: openTrades,
      closedTrades: closedTrades,
    );

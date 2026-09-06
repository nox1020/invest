import 'package:flutter/material.dart';
import 'package:invest/domain/models/iran_inflation.dart';
import 'package:invest/domain/models/metrics.dart';
import 'package:invest/domain/services/iran_inflation_service.dart';
import 'package:invest/domain/utils/dates.dart';
import 'package:invest/domain/utils/money.dart';
import 'package:invest/state/app_state.dart';
import 'package:invest/ui/theme/app_theme.dart';
import 'package:invest/ui/widgets/value_line_chart.dart';
import 'package:provider/provider.dart';
import 'package:shamsi_date/shamsi_date.dart';

enum InflationMetricKind { pointToPoint, monthly, annual, cpi }

Future<void> openInflationDetail(
  BuildContext context, {
  required IranInflationSnapshot snap,
  required InflationMetricKind kind,
}) {
  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => InflationDetailPage(snap: snap, kind: kind),
    ),
  );
}

class InflationDetailPage extends StatefulWidget {
  const InflationDetailPage({
    super.key,
    required this.snap,
    required this.kind,
  });

  final IranInflationSnapshot snap;
  final InflationMetricKind kind;

  @override
  State<InflationDetailPage> createState() => _InflationDetailPageState();
}

class _InflationDetailPageState extends State<InflationDetailPage> {
  late IranInflationSnapshot _snap;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _snap = widget.snap;
    _ensureLongHistory();
  }

  Future<void> _ensureLongHistory() async {
    if (_snap.history.length >= 18) return;
    setState(() => _loading = true);
    try {
      final fresh =
          await IranInflationService().fetchLatest(historyMonths: 24);
      if (!mounted) return;
      setState(() {
        _snap = fresh;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'تمدید تاریخچه ممکن نشد — نمایش داده فعلی';
      });
    }
  }

  String get _title => switch (widget.kind) {
        InflationMetricKind.pointToPoint => 'تورم نقطه‌به‌نقطه',
        InflationMetricKind.monthly => 'تورم ماهانه',
        InflationMetricKind.annual => 'تورم سالانه (۱۲ماهه)',
        InflationMetricKind.cpi => 'شاخص قیمت مصرف‌کننده',
      };

  String get _subtitle => switch (widget.kind) {
        InflationMetricKind.pointToPoint =>
          'درصد تغییر شاخص نسبت به همان ماه سال قبل',
        InflationMetricKind.monthly => 'درصد تغییر شاخص نسبت به ماه قبل',
        InflationMetricKind.annual =>
          'میانگین شاخص ۱۲ ماه اخیر نسبت به دوره مشابه قبلی',
        InflationMetricKind.cpi => 'سطح شاخص CPI با پایه سال ۱۴۰۰ (=۱۰۰)',
      };

  Color get _color => switch (widget.kind) {
        InflationMetricKind.pointToPoint => const Color(0xFFFF6B6B),
        InflationMetricKind.monthly => const Color(0xFFFF9500),
        InflationMetricKind.annual => const Color(0xFF5B8DEF),
        InflationMetricKind.cpi => AppTheme.positive,
      };

  double get _latest => switch (widget.kind) {
        InflationMetricKind.pointToPoint => _snap.pointToPointPct,
        InflationMetricKind.monthly => _snap.monthlyPct,
        InflationMetricKind.annual => _snap.annualPct,
        InflationMetricKind.cpi => _snap.cpiIndex,
      };

  List<SeriesPoint> get _series {
    return _snap.history.map((p) {
      final day = (p.month >= 1 && p.month <= 12 && p.year > 1300)
          ? toIsoDate(Jalali(p.year, p.month, 15).toDateTime())
          : p.period;
      final value = switch (widget.kind) {
        InflationMetricKind.pointToPoint => p.pointToPointPct,
        InflationMetricKind.monthly => p.monthlyPct,
        InflationMetricKind.annual => p.annualPct,
        InflationMetricKind.cpi => p.cpiIndex,
      };
      return SeriesPoint(date: day, value: value);
    }).toList();
  }

  String _formatValue(double v) {
    if (widget.kind == InflationMetricKind.cpi) {
      return formatNumber(v, decimals: 1);
    }
    return formatPct(v);
  }

  @override
  Widget build(BuildContext context) {
    final calendar = context.watch<AppState>().settings.calendar;
    final series = _series;

    return Scaffold(
      appBar: AppBar(
        title: Text(_title),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.card,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  _title,
                  style: const TextStyle(
                    color: AppTheme.title,
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _formatValue(_latest),
                  textDirection: TextDirection.ltr,
                  style: TextStyle(
                    color: _color,
                    fontSize: 32,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _subtitle,
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    color: AppTheme.muted,
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'دوره: ${_snap.periodLabel}',
                  style: const TextStyle(color: AppTheme.muted, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'روند تاریخی',
            textAlign: TextAlign.right,
            style: TextStyle(
              color: AppTheme.title,
              fontWeight: FontWeight.w800,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppTheme.card,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.border),
            ),
            child: _loading && series.length < 6
                ? const SizedBox(
                    height: 240,
                    child: Center(child: CircularProgressIndicator()),
                  )
                : ValueLineChart(
                    points: series,
                    calendar: calendar,
                    formatValue: _formatValue,
                    valueTitle: _title,
                    lineColor: _color,
                  ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              textAlign: TextAlign.right,
              style: const TextStyle(color: AppTheme.muted, fontSize: 11),
            ),
          ],
          const SizedBox(height: 14),
          Text(
            'منبع: ${_snap.sourceLabel}',
            textAlign: TextAlign.right,
            style: TextStyle(
              color: AppTheme.muted.withValues(alpha: 0.85),
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:invest/domain/models/metrics.dart';
import 'package:invest/domain/services/chart_series.dart';
import 'package:invest/domain/utils/dates.dart';
import 'package:invest/domain/utils/money.dart';
import 'package:invest/ui/theme/app_theme.dart';

class DualCurrencyChart extends StatefulWidget {
  const DualCurrencyChart({
    super.key,
    required this.points,
    required this.calendar,
    this.usdtRate,
    this.lineColor = AppTheme.positive,
    this.height = 260,
  });

  final List<SeriesPoint> points;
  final String calendar;
  final double? usdtRate;
  final Color lineColor;
  final double height;

  @override
  State<DualCurrencyChart> createState() => _DualCurrencyChartState();
}

class _DualCurrencyChartState extends State<DualCurrencyChart> {
  int? _selected;

  List<SeriesPoint> get _series => downsampleSeries(widget.points);

  int get _index {
    final series = _series;
    if (series.isEmpty) return 0;
    final i = _selected ?? series.length - 1;
    return i.clamp(0, series.length - 1);
  }

  void _selectAt(Offset local, double width) {
    final series = _series;
    if (series.isEmpty) return;
    const left = 52.0;
    const right = 52.0;
    final plotW = math.max(1.0, width - left - right);
    final x = (local.dx - left).clamp(0.0, plotW);
    final i = series.length == 1
        ? 0
        : ((x / plotW) * (series.length - 1)).round();
    setState(() => _selected = i.clamp(0, series.length - 1));
  }

  @override
  Widget build(BuildContext context) {
    final series = _series;
    if (series.isEmpty) {
      return SizedBox(
        height: widget.height,
        child: const Center(
          child: Text(
            'نقطه‌ای برای نمودار نیست',
            style: TextStyle(color: AppTheme.muted),
          ),
        ),
      );
    }

    final point = series[_index];
    final usd = tomanToUsd(point.value, widget.usdtRate);
    final first = series.first.value;
    final delta = point.value - first;
    final pct = first.abs() < 1e-9 ? 0.0 : delta / first.abs() * 100;
    final tone = delta > 0
        ? AppTheme.positive
        : delta < 0
            ? AppTheme.negative
            : AppTheme.muted;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    formatDisplayDate(point.date, widget.calendar),
                    textAlign: TextAlign.right,
                    style: const TextStyle(color: AppTheme.muted, fontSize: 12),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    formatMoney(point.value),
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      color: AppTheme.title,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (usd != null)
                    Text(
                      formatUsd(usd),
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        color: Color(0xFFE8C547),
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: tone.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                formatPct(pct),
                style: TextStyle(
                  color: tone,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            _LegendDot(color: widget.lineColor, label: 'تومان'),
            if (usd != null || widget.usdtRate != null) ...[
              const SizedBox(width: 14),
              const _LegendDot(color: Color(0xFFE8C547), label: 'دلار'),
            ],
          ],
        ),
        if (widget.usdtRate != null && widget.usdtRate! > 0) ...[
          const SizedBox(height: 4),
          const Text(
            'یک نمودار با دو مقیاس: چپ تومان، راست دلار',
            textAlign: TextAlign.right,
            style: TextStyle(color: AppTheme.muted, fontSize: 10),
          ),
        ],
        const SizedBox(height: 10),
        SizedBox(
          height: widget.height,
          child: LayoutBuilder(
            builder: (context, constraints) {
              return GestureDetector(
                onTapDown: (d) => _selectAt(d.localPosition, constraints.maxWidth),
                onHorizontalDragUpdate: (d) =>
                    _selectAt(d.localPosition, constraints.maxWidth),
                child: Directionality(
                  textDirection: TextDirection.ltr,
                  child: CustomPaint(
                    size: Size(constraints.maxWidth, widget.height),
                    painter: _ChartPainter(
                      points: series,
                      selected: _index,
                      usdtRate: widget.usdtRate,
                      calendar: widget.calendar,
                      lineColor: widget.lineColor,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(color: AppTheme.muted, fontSize: 11),
        ),
      ],
    );
  }
}

double _tomanDivisor(double maxAbs) {
  if (maxAbs >= 1e9) return 1e9;
  if (maxAbs >= 1e6) return 1e6;
  if (maxAbs >= 1e3) return 1e3;
  return 1;
}

class _ChartPainter extends CustomPainter {
  _ChartPainter({
    required this.points,
    required this.selected,
    required this.usdtRate,
    required this.calendar,
    required this.lineColor,
  });

  final List<SeriesPoint> points;
  final int selected;
  final double? usdtRate;
  final String calendar;
  final Color lineColor;

  static const _gold = Color(0xFFE8C547);
  static const _left = 52.0;
  static const _right = 52.0;
  static const _top = 12.0;
  static const _bottom = 28.0;

  @override
  void paint(Canvas canvas, Size size) {
    final plot = Rect.fromLTWH(
      _left,
      _top,
      math.max(1, size.width - _left - _right),
      math.max(1, size.height - _top - _bottom),
    );

    final values = points.map((p) => p.value).toList();
    var lo = values.reduce(math.min);
    var hi = values.reduce(math.max);
    if ((hi - lo).abs() < 1e-9) {
      final pad = math.max(hi.abs() * 0.08, 1);
      lo -= pad;
      hi += pad;
    } else {
      final pad = (hi - lo) * 0.12;
      lo -= pad;
      hi += pad;
    }
    final span = hi - lo;
    final divisor = _tomanDivisor(math.max(hi.abs(), lo.abs()));
    final showUsd = usdtRate != null && usdtRate! > 0;

    final bg = Paint()
      ..shader = ui.Gradient.linear(
        plot.topLeft,
        plot.bottomLeft,
        [
          lineColor.withValues(alpha: 0.08),
          const Color(0x00000000),
        ],
      );
    canvas.drawRRect(
      RRect.fromRectAndRadius(plot.inflate(4), const Radius.circular(12)),
      bg,
    );

    final grid = Paint()
      ..color = AppTheme.border
      ..strokeWidth = 1;
    const ticks = 4;
    final labelStyle = TextStyle(
      color: AppTheme.muted,
      fontSize: 9,
      fontFamily: 'Tahoma',
    );
    for (var i = 0; i <= ticks; i++) {
      final t = i / ticks;
      final y = plot.bottom - t * plot.height;
      canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), grid);
      final toman = lo + span * t;
      _paintLabel(
        canvas,
        _formatScaled(toman / divisor),
        Offset(plot.left - 6, y),
        labelStyle,
        alignEnd: true,
      );
      if (showUsd) {
        _paintLabel(
          canvas,
          formatUsd(toman / usdtRate!, compact: true),
          Offset(plot.right + 6, y),
          labelStyle.copyWith(color: _gold.withValues(alpha: 0.9)),
          alignEnd: false,
        );
      }
    }

    Offset pointAt(int i) {
      final x = points.length == 1
          ? plot.center.dx
          : plot.left + plot.width * i / (points.length - 1);
      final y = plot.bottom - ((values[i] - lo) / span) * plot.height;
      return Offset(x, y);
    }

    final path = Path();
    if (points.length == 1) {
      final y = pointAt(0).dy;
      path
        ..moveTo(plot.left, y)
        ..lineTo(plot.right, y);
    } else {
      for (var i = 0; i < points.length; i++) {
        final p = pointAt(i);
        if (i == 0) {
          path.moveTo(p.dx, p.dy);
        } else {
          path.lineTo(p.dx, p.dy);
        }
      }
    }

    final fill = Path.from(path)
      ..lineTo(
        points.length == 1 ? plot.right : pointAt(points.length - 1).dx,
        plot.bottom,
      )
      ..lineTo(points.length == 1 ? plot.left : pointAt(0).dx, plot.bottom)
      ..close();
    canvas.drawPath(
      fill,
      Paint()
        ..shader = ui.Gradient.linear(
          plot.topCenter,
          plot.bottomCenter,
          [
            lineColor.withValues(alpha: 0.28),
            lineColor.withValues(alpha: 0.02),
          ],
        ),
    );

    canvas.drawPath(
      path,
      Paint()
        ..color = lineColor.withValues(alpha: 0.35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = lineColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = points.length > 80 ? 2 : 2.6
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );

    final sel = pointAt(selected.clamp(0, points.length - 1));
    canvas.drawLine(
      Offset(sel.dx, plot.top),
      Offset(sel.dx, plot.bottom),
      Paint()
        ..color = AppTheme.title.withValues(alpha: 0.28)
        ..strokeWidth = 1,
    );
    canvas.drawCircle(sel, 8, Paint()..color = lineColor.withValues(alpha: 0.25));
    canvas.drawCircle(sel, 4.5, Paint()..color = AppTheme.title);
    canvas.drawCircle(
      sel,
      4.5,
      Paint()
        ..color = lineColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    final xLabels = _xIndexes(points.length);
    for (final i in xLabels) {
      final p = pointAt(i);
      _paintLabel(
        canvas,
        formatChartTickDate(points[i].date, calendar),
        Offset(p.dx, plot.bottom + 8),
        labelStyle,
        alignEnd: false,
        center: true,
      );
    }
  }

  List<int> _xIndexes(int n) {
    if (n <= 1) return const [0];
    if (n == 2) return const [0, 1];
    return [0, n ~/ 2, n - 1];
  }

  String _formatScaled(double v) {
    final abs = v.abs();
    final decimals = abs >= 100 || (abs - abs.round()).abs() < 0.05 ? 0 : 1;
    return formatNumber(v, decimals: decimals);
  }

  void _paintLabel(
    Canvas canvas,
    String text,
    Offset pos,
    TextStyle style, {
    required bool alignEnd,
    bool center = false,
  }) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    var dx = pos.dx;
    if (center) {
      dx -= tp.width / 2;
    } else if (alignEnd) {
      dx -= tp.width;
    }
    tp.paint(canvas, Offset(dx, pos.dy - tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant _ChartPainter oldDelegate) =>
      oldDelegate.points != points ||
      oldDelegate.selected != selected ||
      oldDelegate.usdtRate != usdtRate ||
      oldDelegate.calendar != calendar ||
      oldDelegate.lineColor != lineColor;
}

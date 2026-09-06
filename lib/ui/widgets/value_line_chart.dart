import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:invest/domain/models/metrics.dart';
import 'package:invest/domain/services/chart_series.dart';
import 'package:invest/domain/utils/dates.dart';
import 'package:invest/ui/theme/app_theme.dart';

typedef ValueLabelBuilder = String Function(double value);

/// Single-series interactive line chart for index detail pages.
class ValueLineChart extends StatefulWidget {
  const ValueLineChart({
    super.key,
    required this.points,
    required this.calendar,
    required this.formatValue,
    this.lineColor = AppTheme.positive,
    this.height = 240,
    this.valueTitle = 'مقدار',
  });

  final List<SeriesPoint> points;
  final String calendar;
  final ValueLabelBuilder formatValue;
  final Color lineColor;
  final double height;
  final String valueTitle;

  @override
  State<ValueLineChart> createState() => _ValueLineChartState();
}

class _ValueLineChartState extends State<ValueLineChart> {
  int? _selected;

  List<SeriesPoint> get _series => downsampleSeries(widget.points);

  int get _index {
    final series = _series;
    if (series.isEmpty) return 0;
    return (_selected ?? series.length - 1).clamp(0, series.length - 1);
  }

  void _selectAt(Offset local, double width) {
    final series = _series;
    if (series.isEmpty) return;
    const left = 54.0;
    const right = 12.0;
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
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    formatDisplayDate(point.date, widget.calendar),
                    style: const TextStyle(color: AppTheme.muted, fontSize: 12),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    widget.formatValue(point.value),
                    textDirection: TextDirection.ltr,
                    style: const TextStyle(
                      color: AppTheme.title,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    widget.valueTitle,
                    style: const TextStyle(color: AppTheme.muted, fontSize: 11),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: tone.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '${pct >= 0 ? '+' : ''}${pct.toStringAsFixed(2)}٪',
                style: TextStyle(
                  color: tone,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: widget.height,
          child: LayoutBuilder(
            builder: (context, constraints) {
              return GestureDetector(
                onTapDown: (d) =>
                    _selectAt(d.localPosition, constraints.maxWidth),
                onHorizontalDragUpdate: (d) =>
                    _selectAt(d.localPosition, constraints.maxWidth),
                child: Directionality(
                  textDirection: TextDirection.ltr,
                  child: CustomPaint(
                    size: Size(constraints.maxWidth, widget.height),
                    painter: _ValueChartPainter(
                      points: series,
                      selected: _index,
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

class _ValueChartPainter extends CustomPainter {
  _ValueChartPainter({
    required this.points,
    required this.selected,
    required this.calendar,
    required this.lineColor,
  });

  final List<SeriesPoint> points;
  final int selected;
  final String calendar;
  final Color lineColor;

  static const _left = 54.0;
  static const _right = 12.0;
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

    final bg = Paint()
      ..shader = ui.Gradient.linear(
        plot.topLeft,
        plot.bottomLeft,
        [lineColor.withValues(alpha: 0.10), const Color(0x00000000)],
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
      final v = lo + span * t;
      _paintLabel(
        canvas,
        _shortLabel(v),
        Offset(plot.left - 6, y),
        labelStyle,
        alignEnd: true,
      );
    }

    Offset pt(int i) {
      final x = points.length == 1
          ? plot.left + plot.width / 2
          : plot.left + plot.width * (i / (points.length - 1));
      final y = plot.bottom - ((points[i].value - lo) / span) * plot.height;
      return Offset(x, y);
    }

    final path = Path()..moveTo(pt(0).dx, pt(0).dy);
    for (var i = 1; i < points.length; i++) {
      path.lineTo(pt(i).dx, pt(i).dy);
    }
    final fill = Path.from(path)
      ..lineTo(pt(points.length - 1).dx, plot.bottom)
      ..lineTo(pt(0).dx, plot.bottom)
      ..close();
    canvas.drawPath(
      fill,
      Paint()..color = lineColor.withValues(alpha: 0.14),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = lineColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    final sel = pt(selected);
    canvas.drawLine(
      Offset(sel.dx, plot.top),
      Offset(sel.dx, plot.bottom),
      Paint()
        ..color = lineColor.withValues(alpha: 0.35)
        ..strokeWidth = 1,
    );
    canvas.drawCircle(sel, 5, Paint()..color = lineColor);
    canvas.drawCircle(sel, 2.5, Paint()..color = Colors.white);

    final first = points.first.date;
    final last = points.last.date;
    _paintLabel(
      canvas,
      formatChartTickDate(first, calendar),
      Offset(plot.left, size.height - 8),
      labelStyle,
    );
    _paintLabel(
      canvas,
      formatChartTickDate(last, calendar),
      Offset(plot.right, size.height - 8),
      labelStyle,
      alignEnd: true,
    );
  }

  String _shortLabel(double v) {
    final abs = v.abs();
    if (abs >= 1e9) return '${(v / 1e9).toStringAsFixed(1)}B';
    if (abs >= 1e6) return '${(v / 1e6).toStringAsFixed(1)}M';
    if (abs >= 1e3) return '${(v / 1e3).toStringAsFixed(1)}K';
    if (abs >= 100) return v.toStringAsFixed(0);
    if (abs >= 10) return v.toStringAsFixed(1);
    return v.toStringAsFixed(2);
  }

  void _paintLabel(
    Canvas canvas,
    String text,
    Offset at,
    TextStyle style, {
    bool alignEnd = false,
  }) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    final offset = alignEnd
        ? Offset(at.dx - tp.width, at.dy - tp.height / 2)
        : Offset(at.dx, at.dy - tp.height / 2);
    tp.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(covariant _ValueChartPainter oldDelegate) =>
      oldDelegate.points != points ||
      oldDelegate.selected != selected ||
      oldDelegate.lineColor != lineColor ||
      oldDelegate.calendar != calendar;
}

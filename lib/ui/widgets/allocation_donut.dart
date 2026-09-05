import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:invest/ui/theme/app_theme.dart';

class AllocationSlice {
  const AllocationSlice({
    required this.label,
    required this.share,
    required this.color,
  });

  final String label;
  final double share;
  final Color color;
}

class AllocationDonut extends StatelessWidget {
  const AllocationDonut({
    super.key,
    required this.slices,
    this.size = 132,
  });

  final List<AllocationSlice> slices;
  final double size;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _DonutPainter(slices: slices),
    );
  }
}

class _DonutPainter extends CustomPainter {
  _DonutPainter({required this.slices});

  final List<AllocationSlice> slices;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.width * 0.24;
    final rect = Offset.zero & size;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.butt;

    final total = slices.fold<double>(0, (s, e) => s + e.share);
    if (total <= 0) {
      paint.color = AppTheme.border;
      canvas.drawArc(
        rect.deflate(stroke / 2),
        -math.pi / 2,
        math.pi * 2,
        false,
        paint,
      );
      return;
    }

    var start = -math.pi / 2;
    for (final slice in slices) {
      final sweep = math.pi * 2 * (slice.share / total);
      if (sweep <= 0) continue;
      paint.color = slice.color;
      canvas.drawArc(rect.deflate(stroke / 2), start, sweep, false, paint);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter oldDelegate) =>
      oldDelegate.slices != slices;
}

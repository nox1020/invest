import 'package:flutter/material.dart';
import 'package:invest/domain/services/gold_column.dart';
import 'package:invest/ui/gold/gold_format.dart';
import 'package:invest/ui/theme/app_theme.dart';
import 'package:invest/ui/widgets/dashboard_kit.dart';

/// «ستون قیمت طلا»: one vertical column, red at the period low (bottom) to
/// green at the high (top); a white marker at the current price, a faint
/// mark at the previous day's price with an arrow for the move, and a thin
/// tick at the period average. A gold badge flags a price under the average.
class GoldPriceColumnCard extends StatelessWidget {
  const GoldPriceColumnCard({super.key, required this.model, this.columnHeight = 200});

  final GoldColumnModel model;

  /// Height of the column itself (low to high).
  final double columnHeight;

  static const _green = AppTheme.positive;
  static const _red = AppTheme.negative;

  @override
  Widget build(BuildContext context) {
    final m = model;
    final days = fa('${m.days}');
    return Semantics(
      container: true,
      label: goldColumnSemantics(m),
      excludeSemantics: true,
      child: Container(
        key: const ValueKey('gpc-card'),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: AppTheme.card,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppTheme.border),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('قیمت هر گرم طلای ۱۸ عیار',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: AppTheme.title, fontSize: 13, fontWeight: FontWeight.w900)),
          const SizedBox(height: 1),
          Text(
            [
              'ستون: کف تا سقف $days روز اخیر · نشانگر: قیمت الان',
              if (m.hasRange && m.daysWithData < 20) 'داده‌ی ${fa('${m.daysWithData}')} روز',
            ].join(' · '),
            key: const ValueKey('gpc-sub'),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: mutedStyle(10),
          ),
          if (!m.hasPrice)
            const Padding(
              key: ValueKey('gpc-empty'),
              padding: EdgeInsets.only(top: 10),
              child: GNote(
                'هنوز قیمت طلا دریافت نشده. با اتصال به اینترنت، قیمت الان روی ستون می‌نشیند.',
                color: AppTheme.muted,
                icon: Icons.info_outline,
              ),
            )
          else ...[
            const SizedBox(height: 6),
            _Stage(model: m, height: columnHeight),
            if (!m.hasRange)
              Padding(
                key: const ValueKey('gpc-partial'),
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'کف و سقف $days روز با ثبت قیمت روزانه کامل می‌شود · تا حالا ${fa('${m.daysWithData}')} روز ثبت شده.',
                  style: mutedStyle(10.5),
                ),
              ),
          ],
        ]),
      ),
    );
  }
}

/// Persian screen-reader text for the column.
String goldColumnSemantics(GoldColumnModel m) {
  if (!m.hasPrice) return 'ستون قیمت طلا: هنوز قیمتی دریافت نشده.';
  final days = fa('${m.days}');
  final parts = <String>['ستون قیمت هر گرم طلای ۱۸ عیار', 'قیمت الان ${gToman(m.price!)} تومان'];
  final pct = m.changePct;
  final ref = m.referenceDaysAgo == null || m.referenceDaysAgo! <= 1 ? 'دیروز' : '${fa('${m.referenceDaysAgo}')} روز پیش';
  switch (m.direction) {
    case GoldColumnDirection.up:
      parts.add('${gNum(pct!.abs(), decimals: 1)} درصد بالاتر از $ref');
    case GoldColumnDirection.down:
      parts.add('${gNum(pct!.abs(), decimals: 1)} درصد پایین‌تر از $ref');
    case GoldColumnDirection.flat:
      parts.add('بدون تغییر نسبت به $ref');
    case null:
      break;
  }
  if (m.hasRange) {
    parts.add('کف $days روز ${gToman(m.low!)} و سقف ${gToman(m.high!)} تومان');
    parts.add('قیمت در ${gNum(m.position! * 100, decimals: 0)} درصد بازه است');
  } else {
    parts.add('کف و سقف هنوز کامل نشده');
  }
  if (m.average != null) {
    parts.add('میانگین $days روز ${gToman(m.average!)} تومان');
    if (m.belowAverage) {
      parts.add('قیمت ${gNum(m.belowAveragePct!, decimals: 1)} درصد (${gToman(m.belowAverageGap!)} تومان) زیر میانگین است');
    }
  }
  return parts.join('، ');
}

class _Stage extends StatelessWidget {
  const _Stage({required this.model, required this.height});
  final GoldColumnModel model;
  final double height;

  static const pad = 22.0;

  @override
  Widget build(BuildContext context) {
    final m = model;
    final range = m.hasRange;
    final days = fa('${m.days}');
    final dir = m.direction;
    final moveColor = switch (dir) {
      GoldColumnDirection.up => GoldPriceColumnCard._green,
      GoldColumnDirection.down => GoldPriceColumnCard._red,
      _ => kGold,
    };
    final refLabel = m.referenceDaysAgo == null || m.referenceDaysAgo! <= 1
        ? 'دیروز'
        : '${fa('${m.referenceDaysAgo}')} روز پیش';
    return _Anim(
      end: m.position ?? 0.5,
      builder: (pos) => _Anim(
        end: m.referencePosition ?? -1,
        builder: (ref) => _Anim(
          end: m.averagePosition ?? -1,
          builder: (avg) {
            // On a flat range every mark is the same price: keep only the ends.
            final hasRef = range && !m.flatRange && m.referencePosition != null;
            final hasAvg = range && !m.flatRange && m.averagePosition != null;
            return SizedBox(
              height: height + 2 * pad,
              child: CustomMultiChildLayout(
                delegate: _StageLayout(
                  pad: pad,
                  height: height,
                  pos: pos,
                  ref: hasRef ? ref : null,
                  avg: hasAvg ? avg : null,
                ),
                children: [
                  LayoutId(
                    id: _Slot.column,
                    child: CustomPaint(
                      key: const ValueKey('gpc-column'),
                      size: Size(_StageLayout.colBox, height + 2 * pad),
                      painter: _ColumnPainter(
                        pad: pad,
                        pos: pos,
                        ref: hasRef ? ref : null,
                        avg: hasAvg ? avg : null,
                        range: range,
                        moveColor: dir == GoldColumnDirection.flat ? null : moveColor,
                      ),
                    ),
                  ),
                  if (range) ...[
                    LayoutId(
                        id: _Slot.high,
                        child: _Label('سقف $days روز', gToman(m.high!), key: const ValueKey('gpc-high'))),
                    LayoutId(
                        id: _Slot.low, child: _Label('کف $days روز', gToman(m.low!), key: const ValueKey('gpc-low'))),
                    if (hasRef)
                      LayoutId(
                          id: _Slot.ref,
                          child: _Label(refLabel, gToman(m.reference!), muted: true, key: const ValueKey('gpc-ref'))),
                    if (hasAvg)
                      LayoutId(
                          id: _Slot.avg,
                          child: _Label('میانگین $days روز', gToman(m.average!),
                              color: kGoldText, key: const ValueKey('gpc-avg'))),
                  ],
                  LayoutId(id: _Slot.bubble, child: _Bubble(model: m, color: moveColor, refLabel: refLabel)),
                  if (m.belowAverage)
                    LayoutId(
                      id: _Slot.badge,
                      child: _BelowAverageBadge(
                          key: const ValueKey('gpc-below-avg'), pct: m.belowAveragePct!, days: m.days),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Animates a fraction to [end] (0..1; negative = absent, drawn as is).
class _Anim extends StatelessWidget {
  const _Anim({required this.end, required this.builder});
  final double end;
  final Widget Function(double) builder;

  @override
  Widget build(BuildContext context) {
    if (end < 0) return builder(end);
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: end),
      duration: const Duration(milliseconds: 650),
      curve: Curves.easeOutCubic,
      builder: (_, v, __) => builder(v),
    );
  }
}

enum _Slot { column, high, low, ref, avg, bubble, badge }

/// Column on the right part (RTL start side reads the scale first), the
/// scale labels to its right, the price bubble (and badge) to its left.
class _StageLayout extends MultiChildLayoutDelegate {
  _StageLayout({required this.pad, required this.height, required this.pos, this.ref, this.avg});

  final double pad;
  final double height;
  final double pos;
  final double? ref;
  final double? avg;

  /// Width of the painted column box (track, notches, move arrow).
  static const colBox = 56.0;

  double _y(double f) => pad + (1 - f.clamp(0.0, 1.0)) * height;

  @override
  void performLayout(Size size) {
    final total = size.height;
    final labelMax = size.width * 0.36;
    final loose = BoxConstraints(maxWidth: labelMax, maxHeight: total);
    final sizes = <_Slot, Size>{};
    for (final s in const [_Slot.high, _Slot.low, _Slot.ref, _Slot.avg]) {
      if (hasChild(s)) sizes[s] = layoutChild(s, loose);
    }
    var labelW = 0.0;
    for (final s in sizes.values) {
      if (s.width > labelW) labelW = s.width;
    }
    final colX = (size.width - labelW - 6 - colBox).clamp(0.0, size.width - colBox);
    layoutChild(_Slot.column, BoxConstraints.tight(Size(colBox, total)));
    positionChild(_Slot.column, Offset(colX, 0));
    final labelX = colX + colBox + 6;

    double clampTop(double centre, double h, double lo, double hi) {
      final top = centre - h / 2;
      return top.clamp(lo, (hi - h) < lo ? lo : hi - h);
    }

    final hiS = sizes[_Slot.high], loS = sizes[_Slot.low];
    var innerTop = 0.0, innerBottom = total;
    if (hiS != null) {
      final t = clampTop(_y(1), hiS.height, 0, total);
      positionChild(_Slot.high, Offset(labelX, t));
      innerTop = t + hiS.height + 4;
    }
    if (loS != null) {
      final t = clampTop(_y(0), loS.height, 0, total);
      positionChild(_Slot.low, Offset(labelX, t));
      innerBottom = t - 4;
    }
    // Reference and average labels between high and low, kept apart.
    final mids = <(_Slot, double, Size)>[
      if (ref != null && sizes[_Slot.ref] != null) (_Slot.ref, _y(ref!), sizes[_Slot.ref]!),
      if (avg != null && sizes[_Slot.avg] != null) (_Slot.avg, _y(avg!), sizes[_Slot.avg]!),
    ]..sort((a, b) => a.$2.compareTo(b.$2));
    final tops = [for (final e in mids) clampTop(e.$2, e.$3.height, innerTop, innerBottom)];
    const gap = 5.0;
    if (mids.length == 2 && tops[0] + mids[0].$3.height + gap > tops[1]) {
      final need = mids[0].$3.height + gap + mids[1].$3.height;
      final centre = (tops[0] + tops[1] + mids[1].$3.height) / 2;
      var a = centre - need / 2;
      if (a < innerTop) a = innerTop;
      if (a + need > innerBottom) a = innerBottom - need;
      tops[0] = a;
      tops[1] = a + mids[0].$3.height + gap;
    }
    for (var i = 0; i < mids.length; i++) {
      positionChild(mids[i].$1, Offset(labelX, tops[i]));
    }

    // Bubble left of the column (clear of the move arrow), pointing at it.
    final bubbleMax = colX.clamp(40.0, size.width);
    final b = layoutChild(_Slot.bubble, BoxConstraints(maxWidth: bubbleMax, maxHeight: total));
    final by = clampTop(_y(pos), b.height, 0, total);
    final bx = (colX - b.width).clamp(0.0, size.width - b.width);
    positionChild(_Slot.bubble, Offset(bx, by));
    if (hasChild(_Slot.badge)) {
      final g = layoutChild(_Slot.badge, BoxConstraints(maxWidth: bubbleMax, maxHeight: total));
      final below = by + b.height + 5;
      final gy = below + g.height <= total ? below : (by - 5 - g.height).clamp(0.0, total - g.height);
      final gx = (bx + b.width - g.width - 8).clamp(0.0, size.width - g.width);
      positionChild(_Slot.badge, Offset(gx, gy));
    }
  }

  @override
  bool shouldRelayout(_StageLayout old) =>
      old.pos != pos || old.ref != ref || old.avg != avg || old.height != height || old.pad != pad;
}

class _ColumnPainter extends CustomPainter {
  _ColumnPainter({
    required this.pad,
    required this.pos,
    required this.ref,
    required this.avg,
    required this.range,
    required this.moveColor,
  });

  final double pad;
  final double pos;
  final double? ref;
  final double? avg;
  final bool range;
  final Color? moveColor;

  static const track = 20.0;

  @override
  void paint(Canvas canvas, Size size) {
    final h = size.height - 2 * pad;
    final cx = size.width - 18 - track / 2; // notch room on the right, arrow on the left
    double y(double f) => pad + (1 - f.clamp(0.0, 1.0)) * h;
    final rect = Rect.fromLTWH(cx - track / 2, pad, track, h);
    final rr = RRect.fromRectAndRadius(rect, const Radius.circular(track / 2));
    final fill = Paint();
    if (range) {
      fill.shader = const LinearGradient(
        begin: Alignment.bottomCenter,
        end: Alignment.topCenter,
        colors: [AppTheme.negative, Color(0xFFE5A24A), kGold, AppTheme.positive],
        stops: [0, 0.35, 0.55, 1],
      ).createShader(rect);
    } else {
      fill.color = AppTheme.border;
    }
    canvas.drawRRect(rr, fill..color = fill.color.withValues(alpha: range ? 0.92 : 1));
    final sep = Paint()..color = AppTheme.bg.withValues(alpha: 0.65);
    for (var i = 1; i < 4; i++) {
      canvas.drawRect(Rect.fromLTWH(rect.left, pad + h * i / 4 - 0.75, track, 1.5), sep);
    }
    if (avg != null) {
      final ay = y(avg!);
      // Thin dark line across the track and a gold tick toward the scale.
      canvas.drawRect(Rect.fromLTWH(rect.left, ay - 0.75, track, 1.5), Paint()..color = AppTheme.bg);
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(rect.right + 3, ay - 1, 9, 2), const Radius.circular(1)),
        Paint()..color = kGold,
      );
    }
    if (ref != null) {
      final ry = y(ref!);
      final g = RRect.fromRectAndRadius(Rect.fromLTWH(rect.left - 5, ry - 2, track + 10, 4), const Radius.circular(2));
      canvas.drawRRect(g, Paint()..color = AppTheme.text.withValues(alpha: 0.35));
      canvas.drawRRect(
          g,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1
            ..color = AppTheme.text.withValues(alpha: 0.65));
      final c = moveColor;
      final py = y(pos);
      if (c != null && (py - ry).abs() > 6) {
        final ax = rect.left - 12;
        final p = Paint()
          ..color = c
          ..strokeWidth = 2;
        final up = py < ry;
        canvas.drawLine(Offset(ax, ry), Offset(ax, up ? py + 7 : py - 7), p);
        final head = Path()
          ..moveTo(ax - 5, up ? py + 8 : py - 8)
          ..lineTo(ax + 5, up ? py + 8 : py - 8)
          ..lineTo(ax, up ? py : py)
          ..close();
        canvas.drawPath(head, Paint()..color = c);
      }
    }
    // Current price marker.
    final my = y(range ? pos : 0.5);
    final marker = RRect.fromRectAndRadius(Rect.fromLTWH(rect.left - 8, my - 4, track + 16, 8), const Radius.circular(4));
    canvas.drawRRect(
        marker.inflate(4),
        Paint()
          ..color = Colors.white.withValues(alpha: 0.18)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6));
    canvas.drawRRect(marker.inflate(2), Paint()..color = AppTheme.bg);
    canvas.drawRRect(marker, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(_ColumnPainter old) =>
      old.pos != pos ||
      old.ref != ref ||
      old.avg != avg ||
      old.range != range ||
      old.moveColor != moveColor ||
      old.pad != pad;
}

class _Label extends StatelessWidget {
  const _Label(this.k, this.v, {super.key, this.muted = false, this.color});
  final String k;
  final String v;
  final bool muted;
  final Color? color;

  @override
  Widget build(BuildContext context) => FittedBox(
        fit: BoxFit.scaleDown,
        alignment: AlignmentDirectional.centerStart,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text(k,
              maxLines: 1,
              style: TextStyle(color: color ?? AppTheme.muted, fontSize: 9.5, fontWeight: FontWeight.w700, height: 1.35)),
          Text(v,
              maxLines: 1,
              style: TextStyle(
                  color: color ?? (muted ? AppTheme.muted : const Color(0xFFCFE3D8)),
                  fontSize: muted ? 11 : 11.5,
                  fontWeight: FontWeight.w900,
                  height: 1.35)),
        ]),
      );
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.model, required this.color, required this.refLabel});
  final GoldColumnModel model;
  final Color color;
  final String refLabel;

  @override
  Widget build(BuildContext context) {
    final m = model;
    final pct = m.changePct;
    final dir = m.direction;
    final arrow = switch (dir) {
      GoldColumnDirection.up => Icons.arrow_drop_up,
      GoldColumnDirection.down => Icons.arrow_drop_down,
      _ => null,
    };
    final changeColor = switch (dir) {
      GoldColumnDirection.up => AppTheme.positive,
      GoldColumnDirection.down => AppTheme.negative,
      _ => AppTheme.muted,
    };
    return Row(
      key: const ValueKey('gpc-bubble'),
      mainAxisSize: MainAxisSize.min,
      children: [
        CustomPaint(size: const Size(8, 14), painter: _TipPainter(color)),
        Flexible(
          child: Container(
            padding: const EdgeInsets.fromLTRB(9, 4, 9, 5),
            decoration: BoxDecoration(
              color: AppTheme.bg,
              borderRadius: BorderRadius.circular(11),
              border: Border.all(color: color, width: 1.5),
              boxShadow: const [BoxShadow(color: Color(0x88000000), blurRadius: 18, offset: Offset(0, 6))],
            ),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerStart,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                const Text('الان · تومان',
                    style: TextStyle(color: AppTheme.muted, fontSize: 9, fontWeight: FontWeight.w700, height: 1.3)),
                Text(gToman(m.price!),
                    key: const ValueKey('gpc-price'),
                    style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w900, height: 1.3)),
                if (pct != null)
                  Row(key: const ValueKey('gpc-change'), mainAxisSize: MainAxisSize.min, children: [
                    if (arrow != null) Icon(arrow, size: 16, color: changeColor),
                    Text(
                      dir == GoldColumnDirection.flat
                          ? 'بدون تغییر نسبت به $refLabel'
                          : '${gPct(pct)} · ${gSigned(m.change!)}',
                      style: TextStyle(color: changeColor, fontSize: 10.5, fontWeight: FontWeight.w800, height: 1.3),
                    ),
                  ]),
              ]),
            ),
          ),
        ),
      ],
    );
  }
}

/// Right-pointing tip (toward the column).
class _TipPainter extends CustomPainter {
  _TipPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, size.height / 2)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(p, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_TipPainter old) => old.color != color;
}

/// «زیر میانگین ۳۰ روز · ۲٫۱٪» in a calm gold, not an alarm.
class _BelowAverageBadge extends StatelessWidget {
  const _BelowAverageBadge({super.key, required this.pct, required this.days});
  final double pct;
  final int days;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          color: kGold.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: kGold.withValues(alpha: 0.55)),
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            'زیر میانگین ${fa('$days')} روز · ${gNum(pct, decimals: 1)}٪',
            maxLines: 1,
            style: const TextStyle(color: kGoldText, fontSize: 10, fontWeight: FontWeight.w800),
          ),
        ),
      );
}

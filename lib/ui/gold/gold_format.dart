import 'package:flutter/material.dart';
import 'package:invest/domain/utils/money.dart';
import 'package:invest/ui/theme/app_theme.dart';
import 'package:invest/ui/widgets/dashboard_kit.dart';

/// Formatting shared by the «صندوق طلا» screens. Everything here is Toman
/// (gold is priced in Toman), whatever the app's display currency.

/// `1,234,500` in Persian digits.
String gToman(num v) => fa(formatNumber(v.isFinite ? v.round() : 0));

/// `+1,234` / `−1,234` (sign kept next to the number in RTL).
String gSigned(num v) {
  final r = v.isFinite ? v.round() : 0;
  final sign = r > 0 ? '+' : (r < 0 ? '−' : '');
  return faSigned('$sign${formatNumber(r.abs())}');
}

/// Up to [decimals] decimals, trailing zeros trimmed (`6.934`, `42.5`).
String gNum(num v, {int decimals = 3}) {
  final s = formatNumber(v.isFinite ? v : 0, decimals: decimals);
  if (!s.contains('.')) return fa(s);
  var t = s.replaceFirst(RegExp(r'0+$'), '');
  if (t.endsWith('.')) t = t.substring(0, t.length - 1);
  return fa(t);
}

String gGrams(num g) => '${gNum(g)} گرم';

/// `+1.2٪` with a correctly placed sign.
String gPct(num v, {int decimals = 1, bool sign = true}) {
  final x = v.isFinite ? v : 0;
  final s = sign && x > 0 ? '+' : (x < 0 ? '−' : '');
  return faSigned('$s${formatNumber(x.abs(), decimals: decimals)}٪');
}

/// Compact Toman (`۱۸۵٫۴ میلیون ت`).
String gCompact(num v) => fa(formatCompactToman(v, forceToman: true));

/// Space the system gesture/nav bar takes under the app (Android 15 draws
/// edge-to-edge). Zero while the keyboard covers it. Modal sheets opened with
/// `useSafeArea` don't pad the bottom, so their footers add this themselves.
double gSafeBottom(BuildContext context) {
  final bar = MediaQuery.viewPaddingOf(context).bottom - MediaQuery.viewInsetsOf(context).bottom;
  return bar > 0 ? bar : 0;
}

const kGoldDeep = Color(0xFFC9A743);
const kGoldText = Color(0xFFF1E3B0);
const kSheetBg = Color(0xFF132019);
const kWarn = Color(0xFFE0A040);

/// Plain «key ····· value» line.
class GKv extends StatelessWidget {
  const GKv(this.k, this.v, {super.key, this.color, this.bold = false, this.size = 12, this.valueKey});

  final String k;
  final String v;
  final Color? color;
  final bool bold;
  final double size;
  final Key? valueKey;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2.5),
        child: Row(children: [
          Expanded(
            child: Text(k, maxLines: 2, overflow: TextOverflow.ellipsis, style: mutedStyle(size - 0.5)),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerEnd,
              child: Text(v,
                  key: valueKey,
                  style: TextStyle(
                      color: color ?? AppTheme.title,
                      fontSize: size,
                      fontWeight: bold ? FontWeight.w900 : FontWeight.w700)),
            ),
          ),
        ]),
      );
}

/// «امروز» on the buy day, else «۴۲ روز».
String gDays(int days) => days <= 0 ? 'امروز' : fa('${formatNumber(days)} روز');

/// Small muted chip with how long a lot has been open.
class GDaysChip extends StatelessWidget {
  const GDaysChip(this.days, {super.key});
  final int days;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 5),
        decoration: BoxDecoration(
          color: AppTheme.muted.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: AppTheme.border),
        ),
        child: Text(gDays(days),
            maxLines: 1,
            softWrap: false,
            style: const TextStyle(color: AppTheme.muted, fontSize: 9.5, fontWeight: FontWeight.w700, height: 1.5)),
      );
}

/// Single line of text that shrinks instead of overflowing.
class GFit extends StatelessWidget {
  const GFit(this.text, {super.key, required this.style, this.align = AlignmentDirectional.centerStart});
  final String text;
  final TextStyle style;
  final AlignmentGeometry align;

  @override
  Widget build(BuildContext context) => FittedBox(
        fit: BoxFit.scaleDown,
        alignment: align,
        child: Text(text, maxLines: 1, style: style),
      );
}

/// Coloured note box (ok / warn / bad).
class GNote extends StatelessWidget {
  const GNote(this.text, {super.key, required this.color, this.icon, this.child});
  final String text;
  final Color color;
  final IconData? icon;
  final Widget? child;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (icon != null) ...[
            Padding(padding: const EdgeInsets.only(top: 1), child: Icon(icon, size: 15, color: color)),
            const SizedBox(width: 6),
          ],
          Expanded(
            child: child ??
                Text(text, style: TextStyle(color: color, fontSize: 11.5, fontWeight: FontWeight.w700, height: 1.6)),
          ),
        ]),
      );
}

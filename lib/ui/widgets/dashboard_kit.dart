import 'package:flutter/material.dart';
import 'package:invest/ui/theme/app_theme.dart';

/// Small building blocks shared by the dashboard sections.
const kGold = Color(0xFFE0C46A);
const kAmber = Color(0xFFE0A84A);
const kUsd = Color(0xFFE8CF7A);

const _faDigits = '۰۱۲۳۴۵۶۷۸۹';

/// Persian digits, with Persian thousands and decimal separators between
/// digits. Never use on a dollar amount (those stay Latin, left to right).
String fa(String s) {
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    final c = s[i];
    final code = c.codeUnitAt(0);
    if (code >= 48 && code <= 57) {
      b.write(_faDigits[code - 48]);
    } else if ((c == ',' || c == '.') &&
        i > 0 &&
        i + 1 < s.length &&
        _isDigit(s.codeUnitAt(i - 1)) &&
        _isDigit(s.codeUnitAt(i + 1))) {
      b.write(c == ',' ? '٬' : '٫');
    } else {
      b.write(c);
    }
  }
  return b.toString();
}

bool _isDigit(int c) => c >= 48 && c <= 57;

/// Keeps a leading +/− next to its number in right-to-left text
/// ("+۱۲۰ م", not "۱۲۰+ م"): the signed number is isolated left to right.
String signFix(String s) {
  if (s.isEmpty) return s;
  final first = s[0];
  if (first != '+' && first != '−' && first != '-') return s;
  final sp = s.indexOf(' ');
  final num = sp < 0 ? s : s.substring(0, sp);
  final rest = sp < 0 ? '' : s.substring(sp);
  return '\u2066$num\u2069$rest';
}

/// Persian digits and a correctly placed sign.
String faSigned(String s) => signFix(fa(s));

TextStyle mutedStyle(double size, [FontWeight w = FontWeight.w600]) =>
    TextStyle(color: AppTheme.muted, fontSize: size, fontWeight: w);

Color toneOf(num v) => v > 0
    ? AppTheme.positive
    : v < 0
        ? AppTheme.negative
        : AppTheme.muted;

/// ▲ / ▼ beside a colour, so direction never depends on colour alone.
class TrendArrow extends StatelessWidget {
  const TrendArrow(this.value, {super.key, this.size = 20});
  final num value;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (value == 0) return const SizedBox.shrink();
    return Icon(
      value > 0 ? Icons.arrow_drop_up_rounded : Icons.arrow_drop_down_rounded,
      color: toneOf(value),
      size: size,
      semanticLabel: value > 0 ? 'افزایش' : 'کاهش',
    );
  }
}

class DashTag extends StatelessWidget {
  const DashTag(this.text, {super.key, required this.color, this.icon});
  final String text;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 3),
        ],
        Flexible(
          child: Text(text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: color, fontSize: 10.5, fontWeight: FontWeight.w700)),
        ),
      ]),
    );
  }
}

/// Section heading: icon, title, one-line subtitle, optional action.
class DashSection extends StatelessWidget {
  const DashSection({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.actionLabel,
    this.onAction,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 22, bottom: 10),
      child: Row(children: [
        if (icon != null) ...[
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: AppTheme.positive.withValues(alpha: 0.13),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, size: 16, color: AppTheme.positive),
          ),
          const SizedBox(width: 8),
        ],
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: AppTheme.title, fontSize: 16, fontWeight: FontWeight.w800)),
            if (subtitle != null && subtitle!.isNotEmpty)
              Text(subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis, style: mutedStyle(11)),
          ]),
        ),
        if (actionLabel != null)
          TextButton(
            onPressed: onAction,
            style: TextButton.styleFrom(
              foregroundColor: AppTheme.positive,
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 6),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(actionLabel!, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
              const Icon(Icons.chevron_left_rounded, size: 18),
            ]),
          ),
        if (trailing != null) ...[const SizedBox(width: 4), trailing!],
      ]),
    );
  }
}

class DashCard extends StatelessWidget {
  const DashCard({super.key, required this.child, this.onTap, this.padding = const EdgeInsets.all(14)});
  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final body = Container(
      padding: padding,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.border.withValues(alpha: 0.85)),
      ),
      child: child,
    );
    return Material(
      color: AppTheme.card.withValues(alpha: 0.92),
      borderRadius: BorderRadius.circular(18),
      child: onTap == null
          ? body
          : InkWell(onTap: onTap, borderRadius: BorderRadius.circular(18), child: body),
    );
  }
}

/// A rounded progress bar; [fraction] is clamped to 0..1.
class DashBar extends StatelessWidget {
  const DashBar(this.fraction, {super.key, required this.color, this.height = 8});
  final double fraction;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) {
    final f = fraction.isNaN ? 0.0 : fraction.clamp(0.0, 1.0);
    return ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: SizedBox(
        height: height,
        child: Stack(fit: StackFit.expand, children: [
          ColoredBox(color: AppTheme.border.withValues(alpha: 0.6)),
          FractionallySizedBox(
            alignment: AlignmentDirectional.centerStart,
            widthFactor: f,
            child: ColoredBox(color: color),
          ),
        ]),
      ),
    );
  }
}

/// A small stat tile (label, value, optional sub line).
class DashTile extends StatelessWidget {
  const DashTile({
    super.key,
    required this.label,
    required this.value,
    this.valueKey,
    this.sub,
    this.color,
    this.trend,
    this.onTap,
  });

  final String label;
  final String value;
  final Key? valueKey;
  final String? sub;
  final Color? color;
  final num? trend;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final body = Container(
      padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
      decoration: BoxDecoration(
        color: AppTheme.bg.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: mutedStyle(11)),
        const SizedBox(height: 3),
        Row(children: [
          if (trend != null) TrendArrow(trend!, size: 18),
          Flexible(
            child: Text(value,
                key: valueKey,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: color ?? AppTheme.title, fontSize: 13.5, fontWeight: FontWeight.w800)),
          ),
        ]),
        if (sub != null) Text(sub!, maxLines: 1, overflow: TextOverflow.ellipsis, style: mutedStyle(10.5)),
      ]),
    );
    return onTap == null
        ? body
        : InkWell(onTap: onTap, borderRadius: BorderRadius.circular(12), child: body);
  }
}

/// "۵ دقیقه پیش" style age.
String agoFa(DateTime t, {DateTime? now}) {
  final d = (now ?? DateTime.now()).difference(t);
  if (d.inMinutes < 1) return 'همین الان';
  if (d.inMinutes < 60) return fa('${d.inMinutes} دقیقه پیش');
  if (d.inHours < 24) return fa('${d.inHours} ساعت پیش');
  return fa('${d.inDays} روز پیش');
}

String hhmm(DateTime t) {
  final l = t.toLocal();
  return fa('${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}');
}

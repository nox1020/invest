import 'package:flutter/material.dart';
import 'package:invest/domain/models/asset_kind.dart';
import 'package:invest/domain/services/dashboard_snapshot.dart';
import 'package:invest/domain/utils/money.dart';
import 'package:invest/ui/theme/app_theme.dart';
import 'package:invest/ui/widgets/dashboard_kit.dart';

/// «ترکیب ارزش» on the «ارزش پورتفو» page: the gold block (grams, value,
/// share, price per gram), one bar per asset kind and the holdings total.
/// Cost basis and cheques live in the balance sheet below, not here.
class PortfolioValueBreakdown extends StatelessWidget {
  const PortfolioValueBreakdown({super.key, required this.snap});

  final DashboardSnapshot snap;

  @override
  Widget build(BuildContext context) {
    final val = snap.valuation;
    final holdings = snap.holdingsValue;
    final goldG = snap.goldHoldingG;
    final goldValue = val?.goldValue ?? 0;
    final nav = snap.marketValue;
    final goldShare = nav > 0 ? goldValue / nav * 100 : 0.0;
    final groups = [...?val?.groups]..sort((a, b) => b.value.compareTo(a.value));

    return Container(
      key: const ValueKey('pv-breakdown'),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (goldG > 0)
          Container(
            key: const ValueKey('pv-gold-section'),
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [kGold.withValues(alpha: 0.16), Colors.transparent]),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: kGold.withValues(alpha: 0.35)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                const Icon(Icons.diamond_outlined, color: kGold, size: 16),
                const SizedBox(width: 6),
                const Expanded(
                  child: Text('موجودی طلا · پوشش تورم',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: kGold, fontSize: 12.5, fontWeight: FontWeight.w800)),
                ),
                const SizedBox(width: 6),
                Text(fa(formatGrams(goldG)),
                    key: const ValueKey('pv-gold-grams'),
                    style: const TextStyle(color: AppTheme.title, fontSize: 13, fontWeight: FontWeight.w800)),
              ]),
              _row('ارزش (معادل ۱۸ عیار)', fa(formatMoney(goldValue))),
              if (nav > 0)
                _row('سهم از کل پورتفو', fa('${formatNumber(goldShare, decimals: 1)}٪'),
                    c: kGold, key: const ValueKey('pv-gold-share')),
              if (goldValue > 0)
                _row('قیمت هر گرم ۱۸ عیار', fa(formatMoney(goldValue / goldG)), c: AppTheme.muted),
            ]),
          ),
        for (final g in groups)
          _KindBar(
            key: ValueKey('pv-group-${g.kind.name}'),
            label: fa('${g.kind.label} (${g.count})'),
            value: fa(formatCompactToman(g.value)),
            share: holdings > 0 ? g.value / holdings : 0,
            color: g.kind.color,
          ),
        const Divider(color: AppTheme.border, height: 14),
        _row(fa('جمع دارایی‌ها (${snap.holdingCount} قلم)'), fa(formatMoney(holdings)),
            bold: true, key: const ValueKey('pv-holdings-total')),
        if (snap.chequeNav.affectsNav)
          Text('چک‌های باز در ترازنامه آمده و جزو این جمع نیست.',
              style: mutedStyle(10.5)),
      ]),
    );
  }

  static Widget _row(String k, String v, {Color? c, bool bold = false, Key? key}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          Expanded(child: Text(k, maxLines: 1, overflow: TextOverflow.ellipsis, style: mutedStyle(12))),
          const SizedBox(width: 8),
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerEnd,
              child: Text(v,
                  key: key,
                  style: TextStyle(
                      color: c ?? AppTheme.title,
                      fontSize: 12.5,
                      fontWeight: bold ? FontWeight.w800 : FontWeight.w700)),
            ),
          ),
        ]),
      );
}

class _KindBar extends StatelessWidget {
  const _KindBar({
    super.key,
    required this.label,
    required this.value,
    required this.share,
    required this.color,
  });

  final String label;
  final String value;
  final double share;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final pct = (share * 100).round();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(
            child: Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: AppTheme.text, fontSize: 12.5)),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerEnd,
              child: Text.rich(TextSpan(children: [
                TextSpan(
                    text: value,
                    style: const TextStyle(
                        color: AppTheme.title, fontSize: 12.5, fontWeight: FontWeight.w800)),
                TextSpan(
                    text: '  ${fa('$pct')}٪',
                    style: const TextStyle(
                        color: AppTheme.muted, fontSize: 11.5, fontWeight: FontWeight.w600)),
              ])),
            ),
          ),
        ]),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: share.clamp(0.0, 1.0),
            minHeight: 5,
            backgroundColor: AppTheme.border,
            color: color,
          ),
        ),
      ]),
    );
  }
}

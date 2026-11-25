import 'package:flutter/material.dart';
import 'package:invest/domain/models/asset_kind.dart';
import 'package:invest/domain/services/dashboard_snapshot.dart';
import 'package:invest/domain/utils/money.dart';
import 'package:invest/ui/theme/app_theme.dart';
import 'package:invest/ui/widgets/dashboard_kit.dart';

/// «ترکیب ارزش» on the «ارزش پورتفو» page: the gold block (grams, value,
/// share, price per gram), one bar per asset kind and the holdings total.
/// Cost basis and cheques live in the balance sheet below, not here.
/// The gold block opens «صندوق طلا» and shows its cash.
class PortfolioValueBreakdown extends StatelessWidget {
  const PortfolioValueBreakdown({super.key, required this.snap, this.onOpenGoldFund});

  final DashboardSnapshot snap;

  /// Opens «صندوق طلا»; the gold block is a button when set.
  final VoidCallback? onOpenGoldFund;

  @override
  Widget build(BuildContext context) {
    final val = snap.valuation;
    final holdings = snap.holdingsValue;
    final goldG = snap.goldHoldingG;
    final goldValue = val?.goldValue ?? 0;
    final nav = snap.marketValue;
    final fundCash = val?.goldFundCash ?? 0;
    final hasFundCash = fundCash.abs() >= 0.5;
    final goldShare = nav > 0 ? goldValue / nav * 100 : 0.0;
    final groups = [...?val?.groups]..sort((a, b) => b.value.compareTo(a.value));
    final barBase = holdings + (fundCash > 0 ? fundCash : 0);

    return Container(
      key: const ValueKey('pv-breakdown'),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (goldG > 0 || fundCash.abs() >= 0.5)
          _GoldBlock(
            goldG: goldG,
            goldValue: goldValue,
            fundCash: fundCash,
            share: nav > 0 ? goldShare : null,
            onTap: onOpenGoldFund,
          ),
        for (final g in groups)
          _KindBar(
            key: ValueKey('pv-group-${g.kind.name}'),
            label: fa('${g.kind.label} (${g.count})'),
            value: fa(formatCompactToman(g.value)),
            share: barBase > 0 ? g.value / barBase : 0,
            color: g.kind.color,
          ),
        if (hasFundCash)
          _KindBar(
            key: const ValueKey('pv-group-gold-fund-cash'),
            label: 'نقد صندوق طلا',
            value: fa(formatCompactToman(fundCash)),
            share: barBase > 0 && fundCash > 0 ? fundCash / barBase : 0,
            color: kFundCash,
          ),
        const Divider(color: AppTheme.border, height: 14),
        _row(fa('جمع دارایی‌ها (${snap.holdingCount} قلم)'), fa(formatMoney(holdings)),
            bold: !hasFundCash, key: const ValueKey('pv-holdings-total')),
        if (hasFundCash)
          _row('جمع دارایی‌ها + نقد صندوق', fa(formatMoney(holdings + fundCash)),
              bold: true, key: const ValueKey('pv-holdings-fund-total')),
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

/// Fund-cash green (a shade darker than [AppTheme.positive]).
const kFundCash = Color(0xFF2FB06A);

/// Gold block: grams, value, fund cash, share; tappable to «صندوق طلا».
class _GoldBlock extends StatelessWidget {
  const _GoldBlock({
    required this.goldG,
    required this.goldValue,
    required this.fundCash,
    required this.share,
    required this.onTap,
  });

  final double goldG;
  final double goldValue;
  final double fundCash;
  final double? share;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tappable = onTap != null;
    final body = Container(
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 4),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [
          kGold.withValues(alpha: tappable ? 0.2 : 0.16),
          kGold.withValues(alpha: 0.03),
        ]),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kGold.withValues(alpha: tappable ? 0.75 : 0.35), width: tappable ? 1.3 : 1),
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
        PortfolioValueBreakdown._row('ارزش (معادل ۱۸ عیار)', fa(formatMoney(goldValue))),
        if (fundCash.abs() >= 0.5)
          PortfolioValueBreakdown._row('نقد صندوق طلا', fa(formatMoney(fundCash)),
              c: fundCash < 0 ? AppTheme.negative : AppTheme.positive, key: const ValueKey('pv-gold-fund-cash')),
        if (share != null)
          PortfolioValueBreakdown._row('سهم از کل پورتفو', fa('${formatNumber(share!, decimals: 1)}٪'),
              c: kGold, key: const ValueKey('pv-gold-share')),
        if (goldValue > 0 && goldG > 0)
          PortfolioValueBreakdown._row('قیمت هر گرم ۱۸ عیار', fa(formatMoney(goldValue / goldG)), c: AppTheme.muted),
        if (tappable) ...[
          const SizedBox(height: 2),
          Container(
            padding: const EdgeInsets.only(top: 6, bottom: 2),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: kGold.withValues(alpha: 0.3))),
            ),
            child: const Row(children: [
              Expanded(
                child: Text('صندوق طلا و ماشین‌حساب خرید و فروش',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: kGold, fontSize: 11.5, fontWeight: FontWeight.w800)),
              ),
              Icon(Icons.chevron_left, color: kGold, size: 18),
            ]),
          ),
        ],
      ]),
    );
    return Padding(
      key: const ValueKey('pv-gold-section'),
      padding: const EdgeInsets.only(bottom: 8),
      child: tappable
          ? Semantics(
              button: true,
              label: 'صندوق طلا',
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  key: const ValueKey('pv-gold-open-fund'),
                  borderRadius: BorderRadius.circular(12),
                  onTap: onTap,
                  child: body,
                ),
              ),
            )
          : body,
    );
  }
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

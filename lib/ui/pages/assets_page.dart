import 'package:flutter/material.dart';
import 'package:invest/domain/models/asset.dart';
import 'package:invest/domain/services/holding_metrics.dart';
import 'package:invest/domain/services/trade_service.dart';
import 'package:invest/domain/utils/money.dart';
import 'package:invest/state/app_state.dart';
import 'package:invest/ui/layout/page_padding.dart';
import 'package:invest/ui/theme/app_theme.dart';
import 'package:invest/ui/widgets/allocation_donut.dart';
import 'package:provider/provider.dart';

const _allocationColors = <Color>[
  Color(0xFFF7931A),
  Color(0xFFE8A598),
  Color(0xFF3DDB7E),
  Color(0xFF5B8DEF),
  Color(0xFF9B8CFF),
  Color(0xFF4ECDC4),
  Color(0xFFE8C547),
  Color(0xFFFF8FAB),
];

Color _colorForAsset(Asset asset) {
  final key = asset.symbol.trim().isNotEmpty ? asset.symbol : asset.name;
  return _allocationColors[key.hashCode.abs() % _allocationColors.length];
}

class AssetsPage extends StatelessWidget {
  const AssetsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final holdings = HoldingMetrics.activeHoldings(
      assets: state.assets,
      openTrades: state.openTrades,
    );

    if (state.assets.isEmpty) {
      return const Center(child: Text('هنوز دارایی ثبت نشده'));
    }
    if (holdings.isEmpty) {
      return const Center(
        child: Text(
          'موجودی بازی برای نمایش نیست',
          style: TextStyle(color: AppTheme.muted),
        ),
      );
    }

    final totalValue =
        holdings.fold<double>(0, (s, h) => s + h.metrics.marketValue);
    final totalPnl =
        holdings.fold<double>(0, (s, h) => s + h.metrics.unrealizedPnl);
    final totalCost =
        holdings.fold<double>(0, (s, h) => s + h.metrics.costBasis);
    final pnlPct = totalCost.abs() < 1e-12 ? 0.0 : totalPnl / totalCost * 100;
    final usdt = state.liveUsdt ?? state.settings.usdtTmnRate;

    return RefreshIndicator(
      onRefresh: () => state.refreshAll(),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: shellPagePadding(extraForFab: state.canMutate),
        children: [
          _PortfolioSummaryRow(
            totalValue: totalValue,
            totalPnl: totalPnl,
            pnlPct: pnlPct,
            usdt: usdt,
          ),
          const SizedBox(height: 18),
          _AllocationSection(holdings: holdings, totalValue: totalValue),
          const SizedBox(height: 16),
          for (var i = 0; i < holdings.length; i++) ...[
            if (i > 0) const SizedBox(height: 10),
            _AssetCard(
              asset: holdings[i].asset,
              metrics: holdings[i].metrics,
              usdt: usdt,
              canMutate: state.canMutate,
            ),
          ],
        ],
      ),
    );
  }
}

class _PortfolioSummaryRow extends StatelessWidget {
  const _PortfolioSummaryRow({
    required this.totalValue,
    required this.totalPnl,
    required this.pnlPct,
    required this.usdt,
  });

  final double totalValue;
  final double totalPnl;
  final double pnlPct;
  final double? usdt;

  @override
  Widget build(BuildContext context) {
    final usdValue = tomanToUsd(totalValue, usdt);
    final usdPnl = tomanToUsd(totalPnl, usdt);
    final pnlPositive = totalPnl >= 0;

    return Row(
      textDirection: TextDirection.ltr,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _SummaryCard(
            title: 'ارزش پورتفو',
            primary: usdValue != null
                ? formatUsd(usdValue)
                : formatCompactToman(totalValue),
            secondary: usdValue != null ? formatCompactToman(totalValue) : null,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _SummaryCard(
            title: 'سود/ضرر تحقق‌نیافته',
            primary: usdPnl != null
                ? formatUsd(usdPnl, showSign: true)
                : formatCompactToman(totalPnl, showSign: true),
            primaryColor: pnlPositive ? AppTheme.positive : AppTheme.negative,
            badge: formatPct(pnlPct),
            leading: Icon(
              pnlPositive ? Icons.arrow_drop_up : Icons.arrow_drop_down,
              color: pnlPositive ? AppTheme.positive : AppTheme.negative,
              size: 22,
            ),
            secondary: usdPnl != null
                ? formatCompactToman(totalPnl, showSign: true)
                : null,
            secondaryColor: pnlPositive ? AppTheme.positive : AppTheme.negative,
          ),
        ),
      ],
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.title,
    required this.primary,
    this.primaryColor,
    this.secondary,
    this.secondaryColor,
    this.badge,
    this.leading,
  });

  final String title;
  final String primary;
  final Color? primaryColor;
  final String? secondary;
  final Color? secondaryColor;
  final String? badge;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            textAlign: TextAlign.right,
            style: const TextStyle(
              color: AppTheme.muted,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            textDirection: TextDirection.ltr,
            alignment: WrapAlignment.end,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 4,
            children: [
              if (leading != null) leading!,
              Text(
                primary,
                style: TextStyle(
                  color: primaryColor ?? AppTheme.title,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  height: 1.15,
                ),
              ),
              if (badge != null)
                Text(
                  badge!,
                  style: TextStyle(
                    color: primaryColor ?? AppTheme.title,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
            ],
          ),
          if (secondary != null) ...[
            const SizedBox(height: 4),
            Text(
              secondary!,
              textAlign: TextAlign.right,
              style: TextStyle(
                color: secondaryColor ?? AppTheme.muted,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _AllocationSection extends StatelessWidget {
  const _AllocationSection({
    required this.holdings,
    required this.totalValue,
  });

  final List<({Asset asset, HoldingMetrics metrics})> holdings;
  final double totalValue;

  @override
  Widget build(BuildContext context) {
    final slices = <AllocationSlice>[];
    for (final h in holdings) {
      if (h.metrics.marketValue <= 0) continue;
      slices.add(
        AllocationSlice(
          label: h.asset.symbol.trim().isNotEmpty
              ? h.asset.symbol.trim()
              : h.asset.name,
          share: totalValue <= 0 ? 0 : h.metrics.marketValue / totalValue,
          color: _colorForAsset(h.asset),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'توزیع دارایی',
          textAlign: TextAlign.right,
          style: TextStyle(
            color: AppTheme.title,
            fontWeight: FontWeight.bold,
            fontSize: 13,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          textDirection: TextDirection.ltr,
          children: [
            Expanded(
              child: slices.isEmpty
                  ? const Text(
                      'موجودی برای نمودار نیست',
                      style: TextStyle(color: AppTheme.muted, fontSize: 12),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final slice in slices.take(6))
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Row(
                              children: [
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    color: slice.color,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Flexible(
                                  child: Text(
                                    '${slice.label}  ${formatNumber(slice.share * 100, decimals: 2)}%',
                                    style: const TextStyle(
                                      color: AppTheme.text,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
            ),
            const SizedBox(width: 16),
            AllocationDonut(slices: slices),
          ],
        ),
      ],
    );
  }
}

class _AssetCard extends StatelessWidget {
  const _AssetCard({
    required this.asset,
    required this.metrics,
    required this.usdt,
    required this.canMutate,
  });

  final Asset asset;
  final HoldingMetrics metrics;
  final double? usdt;
  final bool canMutate;

  @override
  Widget build(BuildContext context) {
    final usdValue = tomanToUsd(metrics.marketValue, usdt);
    final usdPnl = tomanToUsd(metrics.unrealizedPnl, usdt);
    final usdPrice = tomanToUsd(metrics.currentPrice, usdt);
    final usdAvg = tomanToUsd(metrics.avgBuyPrice, usdt);
    final qtyDecimals =
        (metrics.quantity - metrics.quantity.roundToDouble()).abs() < 1e-9
            ? 0
            : 4;
    final qtyLabel = asset.symbol.trim().isEmpty
        ? formatNumber(metrics.quantity, decimals: qtyDecimals)
        : '${formatNumber(metrics.quantity, decimals: qtyDecimals)} ${asset.symbol.trim()}';
    final pnlTone =
        metrics.unrealizedPnl >= 0 ? AppTheme.positive : AppTheme.negative;

    return Material(
      color: AppTheme.card,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: canMutate ? () => showAssetEditor(context, edit: asset) : null,
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.border),
          ),
          child: Column(
            children: [
              Row(
                textDirection: TextDirection.ltr,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _AssetAvatar(asset: asset),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          asset.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppTheme.title,
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          qtyLabel,
                          style: const TextStyle(
                            color: AppTheme.muted,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        usdValue != null
                            ? formatUsd(usdValue, compact: true)
                            : formatCompactToman(metrics.marketValue),
                        style: const TextStyle(
                          color: AppTheme.title,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      if (usdValue != null)
                        Text(
                          formatCompactToman(metrics.marketValue),
                          style: const TextStyle(
                            color: AppTheme.muted,
                            fontSize: 12,
                          ),
                        ),
                    ],
                  ),
                  if (canMutate)
                    PopupMenuButton<String>(
                      padding: EdgeInsets.zero,
                      icon: const Icon(
                        Icons.more_horiz,
                        color: AppTheme.muted,
                      ),
                      onSelected: (value) {
                        if (value == 'edit') {
                          showAssetEditor(context, edit: asset);
                        }
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(
                          value: 'edit',
                          child: Text('ویرایش'),
                        ),
                      ],
                    ),
                ],
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 10),
                child: Divider(height: 1, color: AppTheme.border),
              ),
              _StatRow(
                label: 'سود/ضرر',
                value: usdPnl != null
                    ? formatUsd(usdPnl, compact: true, showSign: true)
                    : formatCompactToman(metrics.unrealizedPnl, showSign: true),
                secondary: usdPnl != null
                    ? formatCompactToman(metrics.unrealizedPnl, showSign: true)
                    : null,
                pct: metrics.unrealizedPnlPct,
                valueColor: pnlTone,
              ),
              _StatRow(
                label: 'میانگین خرید',
                value: usdAvg != null
                    ? formatUsd(usdAvg)
                    : formatMoney(metrics.avgBuyPrice),
                secondary: usdAvg != null
                    ? formatMoney(metrics.avgBuyPrice)
                    : null,
              ),
              _StatRow(
                label: 'قیمت لحظه‌ای',
                value: usdPrice != null
                    ? formatUsd(usdPrice)
                    : formatMoney(metrics.currentPrice),
                secondary: usdPrice != null
                    ? formatMoney(metrics.currentPrice)
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  const _StatRow({
    required this.label,
    required this.value,
    this.secondary,
    this.pct,
    this.valueColor,
  });

  final String label;
  final String value;
  final String? secondary;
  final double? pct;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final tone = valueColor ?? AppTheme.title;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Text(
            label,
            style: const TextStyle(color: AppTheme.muted, fontSize: 12),
          ),
          const Spacer(),
          if (pct != null) ...[
            _PctBadge(pct: pct!),
            const SizedBox(width: 8),
          ],
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                value,
                style: TextStyle(
                  color: tone,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (secondary != null)
                Text(
                  secondary!,
                  style: TextStyle(
                    color: tone == AppTheme.title ? AppTheme.muted : tone,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PctBadge extends StatelessWidget {
  const _PctBadge({required this.pct});
  final double pct;

  @override
  Widget build(BuildContext context) {
    final positive = pct >= 0;
    final color = positive ? AppTheme.positive : AppTheme.negative;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        formatPct(pct),
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _AssetAvatar extends StatelessWidget {
  const _AssetAvatar({required this.asset});
  final Asset asset;

  @override
  Widget build(BuildContext context) {
    final color = _colorForAsset(asset);
    return CircleAvatar(
      radius: 18,
      backgroundColor: color.withValues(alpha: 0.18),
      child: Icon(_iconFor(asset), color: color, size: 20),
    );
  }
}

IconData _iconFor(Asset asset) {
  final symbol = asset.symbol.toUpperCase();
  final name = asset.name;
  if (symbol.contains('BTC') || name.contains('بیت')) {
    return Icons.currency_bitcoin;
  }
  if (symbol.contains('ETH') || name.contains('اتریوم')) {
    return Icons.token_outlined;
  }
  if (symbol.contains('USDT') ||
      symbol.contains('USD') ||
      name.contains('تتر') ||
      name.contains('دلار')) {
    return Icons.attach_money;
  }
  if (TradeService.isGoldAsset(asset.name, asset.symbol)) {
    return Icons.diamond_outlined;
  }
  return Icons.account_balance_wallet_outlined;
}

Future<void> showAssetEditor(BuildContext context, {Asset? edit}) async {
  final nameCtrl = TextEditingController(text: edit?.name ?? '');
  final symbolCtrl = TextEditingController(text: edit?.symbol ?? '');
  final qtyCtrl =
      TextEditingController(text: edit == null ? '0' : '${edit.quantity}');
  final priceCtrl = TextEditingController(
      text: edit == null ? '' : '${edit.avgBuyPrice}');
  final currentCtrl = TextEditingController(
      text: edit == null ? '' : '${edit.currentPrice}');

  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(edit == null ? 'افزودن دارایی' : 'ویرایش دارایی'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(labelText: 'نام'),
              textAlign: TextAlign.right,
            ),
            TextField(
              controller: symbolCtrl,
              decoration: const InputDecoration(labelText: 'نماد (مثل GOLD)'),
              textAlign: TextAlign.right,
            ),
            if (edit == null) ...[
              TextField(
                controller: qtyCtrl,
                decoration: const InputDecoration(labelText: 'مقدار اولیه'),
                keyboardType: TextInputType.number,
                textAlign: TextAlign.right,
              ),
              TextField(
                controller: priceCtrl,
                decoration: const InputDecoration(labelText: 'قیمت خرید'),
                keyboardType: TextInputType.number,
                textAlign: TextAlign.right,
              ),
            ],
            TextField(
              controller: currentCtrl,
              decoration: const InputDecoration(labelText: 'قیمت فعلی'),
              keyboardType: TextInputType.number,
              textAlign: TextAlign.right,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('انصراف')),
        ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('ذخیره')),
      ],
    ),
  );
  if (ok != true || !context.mounted) return;
  final state = context.read<AppState>();
  final svc = state.tradeService;
  try {
    if (edit == null) {
      await svc.createAsset(
        name: nameCtrl.text,
        symbol: symbolCtrl.text,
        quantity: double.tryParse(qtyCtrl.text) ?? 0,
        avgBuyPrice: double.tryParse(priceCtrl.text) ?? 0,
        currentPrice: double.tryParse(currentCtrl.text) ??
            double.tryParse(priceCtrl.text) ??
            0,
      );
    } else {
      edit.name = nameCtrl.text.trim();
      edit.symbol = symbolCtrl.text.trim();
      final cp = double.tryParse(currentCtrl.text);
      if (cp != null) edit.currentPrice = cp;
      await svc.assets.update(edit);
    }
    await state.refresh();
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }
}

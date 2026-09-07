import 'package:flutter/material.dart';
import 'package:invest/domain/models/asset.dart';
import 'package:invest/domain/models/asset_kind.dart';
import 'package:invest/domain/models/asset_meta.dart';
import 'package:invest/domain/services/holding_metrics.dart';
import 'package:invest/domain/utils/money.dart';
import 'package:invest/state/app_state.dart';
import 'package:invest/ui/layout/page_padding.dart';
import 'package:invest/ui/pages/asset_detail_page.dart';
import 'package:invest/ui/theme/app_theme.dart';
import 'package:invest/ui/widgets/allocation_donut.dart';
import 'package:invest/ui/widgets/asset_editor_sheet.dart';
import 'package:provider/provider.dart';

export 'package:invest/ui/widgets/asset_editor_sheet.dart' show showAssetEditor;

class AssetsPage extends StatelessWidget {
  const AssetsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final holdings = HoldingMetrics.activeHoldings(
      assets: state.assets,
      openTrades: state.openTrades,
    );

    Widget emptyBody(String message) {
      return RefreshIndicator(
        onRefresh: () => state.refreshAll(),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: shellPagePadding(extraForFab: state.canMutate),
          children: [
            SizedBox(height: MediaQuery.sizeOf(context).height * 0.28),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppTheme.muted),
            ),
          ],
        ),
      );
    }

    if (state.assets.isEmpty) {
      return emptyBody('هنوز دارایی ثبت نشده');
    }
    if (holdings.isEmpty) {
      return emptyBody('موجودی بازی برای نمایش نیست');
    }

    final totalValue =
        holdings.fold<double>(0, (s, h) => s + h.metrics.marketValue);
    final totalPnl =
        holdings.fold<double>(0, (s, h) => s + h.metrics.unrealizedPnl);
    final totalCost =
        holdings.fold<double>(0, (s, h) => s + h.metrics.costBasis);
    final pnlPct = totalCost.abs() < 1e-12 ? 0.0 : totalPnl / totalCost * 100;
    final usdt = state.liveUsdt ?? state.settings.usdtTmnRate;
    final totalUsdPnl =
        HoldingMetrics.portfolioUnrealizedPnlUsd(holdings, usdt);
    double? totalUsdPnlPct;
    if (totalUsdPnl != null) {
      var usdCost = 0.0;
      var complete = true;
      for (final h in holdings) {
        final c = h.metrics.costBasisUsd;
        if (c == null) {
          complete = false;
          break;
        }
        usdCost += c;
      }
      if (complete && usdCost.abs() >= 1e-12) {
        totalUsdPnlPct = totalUsdPnl / usdCost * 100;
      }
    }

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
            usdPnl: totalUsdPnl,
            usdPnlPct: totalUsdPnlPct,
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
    this.usdPnl,
    this.usdPnlPct,
  });

  final double totalValue;
  final double totalPnl;
  final double pnlPct;
  final double? usdt;
  final double? usdPnl;
  final double? usdPnlPct;

  @override
  Widget build(BuildContext context) {
    final usdValue = tomanToUsd(totalValue, usdt);
    final tomanPositive = totalPnl >= 0;
    final usdPositive = usdPnl == null ? tomanPositive : usdPnl! >= 0;
    final showUsdPnl = usdPnl != null;
    final pnlTone = showUsdPnl
        ? (usdPositive ? AppTheme.positive : AppTheme.negative)
        : (tomanPositive ? AppTheme.positive : AppTheme.negative);

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
            primary: showUsdPnl
                ? formatUsd(usdPnl!, showSign: true)
                : formatCompactToman(totalPnl, showSign: true),
            primaryColor: pnlTone,
            badge: formatPct(showUsdPnl ? (usdPnlPct ?? 0) : pnlPct),
            leading: Icon(
              (showUsdPnl ? usdPositive : tomanPositive)
                  ? Icons.arrow_drop_up
                  : Icons.arrow_drop_down,
              color: pnlTone,
              size: 22,
            ),
            secondary: showUsdPnl
                ? formatCompactToman(totalPnl, showSign: true)
                : null,
            secondaryColor: tomanPositive
                ? AppTheme.positive
                : AppTheme.negative,
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
      final kind = detectAssetKind(
        name: h.asset.name,
        symbol: h.asset.symbol,
        notes: h.asset.notes,
      );
      final useName = kind == AssetKind.property ||
          kind == AssetKind.vehicle ||
          h.asset.symbol.trim().isEmpty;
      slices.add(
        AllocationSlice(
          label: useName ? h.asset.name : h.asset.symbol.trim(),
          share: totalValue <= 0 ? 0 : h.metrics.marketValue / totalValue,
          color: kind.color,
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
    final usdValue = metrics.marketValueUsd(usdt);
    final usdPnl = metrics.unrealizedPnlUsd(usdt);
    final usdPrice = metrics.currentPriceUsd(usdt);
    // Only the registered USD buy basis — never live USDT conversion.
    final buyUsd = metrics.avgBuyPriceUsd;
    final kind = detectAssetKind(
      name: asset.name,
      symbol: asset.symbol,
      notes: asset.notes,
    );
    final qtyDecimals =
        (metrics.quantity - metrics.quantity.roundToDouble()).abs() < 1e-9
            ? 0
            : 4;
    final qtyNumber = formatNumber(metrics.quantity, decimals: qtyDecimals);
    final unit = kind.unitLabel.isNotEmpty
        ? kind.unitLabel
        : (asset.symbol.trim().isEmpty ? '' : asset.symbol.trim());
    final qtyLabel = unit.isEmpty ? qtyNumber : '$qtyNumber $unit';
    final notesParts = parseAssetNotes(asset.notes);
    final note = assetMetaCardSummary(
      kind,
      notesParts.meta,
      freeNotes: notesParts.freeNotes,
      calendar: context.watch<AppState>().settings.calendar,
    );
    final tomanTone =
        metrics.unrealizedPnl >= 0 ? AppTheme.positive : AppTheme.negative;
    final usdTone = usdPnl == null
        ? tomanTone
        : (usdPnl >= 0 ? AppTheme.positive : AppTheme.negative);
    final showUsdPnl = usdPnl != null;

    return Material(
      color: AppTheme.card,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => openAssetDetail(
          context,
          asset: asset,
        ),
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
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: kind.color.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            kind.label,
                            style: TextStyle(
                              color: kind.color,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (note.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            note,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppTheme.muted,
                              fontSize: 11,
                            ),
                          ),
                        ],
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
                label: 'سود/ضرر دلاری',
                value: showUsdPnl
                    ? formatUsd(usdPnl, compact: true, showSign: true)
                    : '—',
                pct: showUsdPnl ? metrics.unrealizedPnlUsdPct(usdt) : null,
                valueColor: showUsdPnl ? usdTone : AppTheme.muted,
              ),
              _StatRow(
                label: 'سود/ضرر ریالی',
                value: formatCompactToman(
                  metrics.unrealizedPnl,
                  showSign: true,
                ),
                pct: metrics.unrealizedPnlPct,
                valueColor: tomanTone,
              ),
              _StatRow(
                label: kind.isUnitAsset ? 'بهای خرید' : 'میانگین خرید',
                value: formatMoney(metrics.avgBuyPrice),
              ),
              if (buyUsd != null && buyUsd > 0)
                _StatRow(
                  label: 'بهای دلاری خرید',
                  value: formatUsd(buyUsd),
                ),
              _StatRow(
                label: kind.isUnitAsset ? 'ارزش فعلی واحد' : 'قیمت لحظه‌ای',
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
    final kind = detectAssetKind(
      name: asset.name,
      symbol: asset.symbol,
      notes: asset.notes,
    );
    return CircleAvatar(
      radius: 18,
      backgroundColor: kind.color.withValues(alpha: 0.18),
      child: Icon(kind.icon, color: kind.color, size: 20),
    );
  }
}

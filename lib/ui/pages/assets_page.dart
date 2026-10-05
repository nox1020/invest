import 'package:flutter/material.dart';
import 'package:invest/domain/models/asset.dart';
import 'package:invest/domain/models/asset_kind.dart';
import 'package:invest/domain/models/profit_alert.dart';
import 'package:invest/domain/services/holding_metrics.dart';
import 'package:invest/domain/utils/money.dart';
import 'package:invest/state/app_state.dart';
import 'package:invest/ui/layout/page_padding.dart';
import 'package:invest/ui/pages/asset_detail_page.dart';
import 'package:invest/ui/theme/app_theme.dart';
import 'package:invest/ui/widgets/allocation_donut.dart';
import 'package:invest/ui/widgets/asset_editor_sheet.dart';
import 'package:invest/ui/widgets/profit_alert_sheet.dart';
import 'package:provider/provider.dart';

export 'package:invest/ui/widgets/asset_editor_sheet.dart' show showAssetEditor;

String _plainPct(num value) => '${formatNumber(value, decimals: 1)}٪';

/// Economist holdings desk under the «معاملات» tab.
class AssetsPage extends StatefulWidget {
  const AssetsPage({super.key});

  @override
  State<AssetsPage> createState() => _AssetsPageState();
}

class _AssetsPageState extends State<AssetsPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _enter;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _enter = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 520),
    );
    _fade = CurvedAnimation(parent: _enter, curve: Curves.easeOutCubic);
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.03),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _enter, curve: Curves.easeOutCubic));
    _enter.forward();
  }

  @override
  void dispose() {
    _enter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final holdings = HoldingMetrics.activeHoldings(
      assets: state.assets,
      openTrades: state.openTrades,
    );
    final usdt = state.liveUsdt ?? state.settings.usdtTmnRate;
    final openLots = state.openTrades.where((t) => t.quantity > 1e-9).length;

    return RefreshIndicator(
      onRefresh: () => state.refreshAll(),
      child: FadeTransition(
        opacity: _fade,
        child: SlideTransition(
          position: _slide,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: shellPagePadding(extraForFab: state.canMutate),
            children: [
              _StatusRibbon(
                offline: state.offline,
                holdings: holdings.length,
                openLots: openLots,
                assetRows: state.assets.length,
              ),
              const SizedBox(height: 12),
              if (state.assets.isEmpty)
                const _EmptyDesk(
                  title: 'دفتر دارایی خالی است',
                  body: 'با ثبت دارایی یا خرید، موقعیت‌ها اینجا جمع می‌شوند.',
                )
              else if (holdings.isEmpty)
                const _EmptyDesk(
                  title: 'موجودی بازی نیست',
                  body: 'دارایی ثبت شده اما مقدار باز صفر است.',
                )
              else ...[
                _ExposureHero(
                  holdings: holdings,
                  usdt: usdt,
                ),
                const SizedBox(height: 20),
                const _SectionLabel(
                  eyebrow: 'ترکیب',
                  title: 'تخصیص دارایی',
                ),
                const SizedBox(height: 10),
                _AllocationPanel(holdings: holdings),
                const SizedBox(height: 12),
                _KindBreakdown(holdings: holdings),
                const SizedBox(height: 20),
                const _SectionLabel(
                  eyebrow: 'دفتر',
                  title: 'موقعیت‌های باز',
                ),
                const SizedBox(height: 10),
                for (var i = 0; i < holdings.length; i++) ...[
                  if (i > 0) const SizedBox(height: 8),
                  _HoldingLedgerRow(
                    asset: holdings[i].asset,
                    metrics: holdings[i].metrics,
                    totalValue: holdings.fold<double>(
                      0,
                      (s, h) => s + h.metrics.marketValue,
                    ),
                    usdt: usdt,
                    canMutate: state.canMutate,
                  ),
                ],
                const SizedBox(height: 16),
                const _Footnote(
                  text:
                      'ارزش و سود شناور از لات‌های باز و علامت زنده محاسبه می‌شود. '
                      'جزئیات میانگین خرید، کارمزد و معاملات در صفحهٔ هر دارایی است.',
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusRibbon extends StatelessWidget {
  const _StatusRibbon({
    required this.offline,
    required this.holdings,
    required this.openLots,
    required this.assetRows,
  });

  final bool offline;
  final int holdings;
  final int openLots;
  final int assetRows;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(
          offline ? Icons.cloud_off_outlined : Icons.account_tree_outlined,
          size: 14,
          color: offline ? AppTheme.negative : AppTheme.muted,
        ),
        const SizedBox(width: 6),
        Text(
          offline ? 'آفلاین' : 'میز دارایی',
          style: TextStyle(
            color: offline ? AppTheme.negative : AppTheme.muted,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            '$holdings موقعیت · $openLots لات · $assetRows دارایی',
            textAlign: TextAlign.left,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppTheme.muted,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.eyebrow, required this.title});

  final String eyebrow;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          eyebrow,
          style: const TextStyle(
            color: AppTheme.muted,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.4,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          title,
          style: const TextStyle(
            color: AppTheme.title,
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

class _EmptyDesk extends StatelessWidget {
  const _EmptyDesk({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.only(
        top: MediaQuery.sizeOf(context).height * 0.12,
      ),
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 28),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [Color(0xFF1C3F30), Color(0xFF13251C)],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        children: [
          const Icon(Icons.insights_outlined, color: AppTheme.muted, size: 36),
          const SizedBox(height: 14),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppTheme.title,
              fontWeight: FontWeight.w800,
              fontSize: 17,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            body,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppTheme.muted, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class _ExposureHero extends StatelessWidget {
  const _ExposureHero({
    required this.holdings,
    required this.usdt,
  });

  final List<({Asset asset, HoldingMetrics metrics})> holdings;
  final double? usdt;

  @override
  Widget build(BuildContext context) {
    final totalValue =
        holdings.fold<double>(0, (s, h) => s + h.metrics.marketValue);
    final totalCost =
        holdings.fold<double>(0, (s, h) => s + h.metrics.costBasis);
    final totalPnl =
        holdings.fold<double>(0, (s, h) => s + h.metrics.unrealizedPnl);
    final pnlPct = totalCost.abs() < 1e-12 ? 0.0 : totalPnl / totalCost * 100;
    final usdValue = HoldingMetrics.portfolioMarketValueUsd(holdings, usdt);
    final usdPnl = HoldingMetrics.portfolioUnrealizedPnlUsd(holdings, usdt);
    double? usdPnlPct;
    if (usdPnl != null) {
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
        usdPnlPct = usdPnl / usdCost * 100;
      }
    }
    final tone = totalPnl >= 0 ? AppTheme.positive : AppTheme.negative;
    final winners =
        holdings.where((h) => h.metrics.unrealizedPnl >= 0).length;
    final losers = holdings.length - winners;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: const LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [
            Color(0xFF1C3F30),
            Color(0xFF13251C),
            Color(0xFF101C16),
          ],
          stops: [0, 0.55, 1],
        ),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Row(
            children: [
              _Pill(text: 'EXPOSURE'),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'ارزش موقعیت‌های باز',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    color: AppTheme.muted,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            formatMoney(totalValue),
            textAlign: TextAlign.right,
            style: const TextStyle(
              color: AppTheme.title,
              fontSize: 26,
              fontWeight: FontWeight.w800,
              height: 1.1,
            ),
          ),
          if (usdValue != null) ...[
            const SizedBox(height: 4),
            Text(
              formatUsd(usdValue),
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: Color(0xFFE8C547),
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            decoration: BoxDecoration(
              color: AppTheme.bg.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: AppTheme.border.withValues(alpha: 0.85),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: _HeroStat(
                    label: 'سود شناور',
                    value: formatCompactToman(totalPnl, showSign: true),
                    tone: tone,
                  ),
                ),
                _VRule(),
                Expanded(
                  child: _HeroStat(
                    label: 'بازده',
                    value: formatPct(pnlPct),
                    tone: tone,
                  ),
                ),
                _VRule(),
                Expanded(
                  child: _HeroStat(
                    label: usdPnl == null ? 'سبز / قرمز' : 'سود دلاری',
                    value: usdPnl == null
                        ? '$winners / $losers'
                        : formatUsd(usdPnl, compact: true, showSign: true),
                    tone: usdPnl == null
                        ? AppTheme.muted
                        : (usdPnl >= 0
                            ? AppTheme.positive
                            : AppTheme.negative),
                  ),
                ),
              ],
            ),
          ),
          if (usdPnlPct != null) ...[
            const SizedBox(height: 8),
            Text(
              'بازده دلاری ${formatPct(usdPnlPct)} · نسبت به بهای خرید ثبت‌شده',
              textAlign: TextAlign.right,
              style: const TextStyle(color: AppTheme.muted, fontSize: 11),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            'بهای تمام‌شده ${formatCompactToman(totalCost)}',
            textAlign: TextAlign.right,
            style: const TextStyle(color: AppTheme.muted, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.bg.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.border),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: AppTheme.muted,
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

class _HeroStat extends StatelessWidget {
  const _HeroStat({
    required this.label,
    required this.value,
    required this.tone,
  });

  final String label;
  final String value;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          label,
          style: const TextStyle(
            color: AppTheme.muted,
            fontSize: 10,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          value,
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: tone,
            fontSize: 13,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

class _VRule extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 28,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      color: AppTheme.border.withValues(alpha: 0.9),
    );
  }
}

class _AllocationPanel extends StatelessWidget {
  const _AllocationPanel({required this.holdings});

  final List<({Asset asset, HoldingMetrics metrics})> holdings;

  @override
  Widget build(BuildContext context) {
    final total =
        holdings.fold<double>(0, (s, h) => s + h.metrics.marketValue);
    final slices = <AllocationSlice>[];
    for (final h in holdings) {
      final mv = h.metrics.marketValue;
      if (mv <= 0) continue;
      final kind = detectAssetKind(
        name: h.asset.name,
        symbol: h.asset.symbol,
        notes: h.asset.notes,
      );
      final label =
          h.asset.symbol.trim().isEmpty ? h.asset.name : h.asset.symbol;
      slices.add(
        AllocationSlice(
          label: label,
          share: total <= 0 ? 0 : mv / total,
          color: kind.color,
        ),
      );
    }
    final top = slices.isEmpty ? null : slices.first;
    final concentration = top == null ? 0.0 : top.share * 100;
    final concentrated = concentration >= 40;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              AllocationDonut(slices: slices, size: 104),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${holdings.length}',
                    style: const TextStyle(
                      color: AppTheme.title,
                      fontWeight: FontWeight.w800,
                      fontSize: 18,
                    ),
                  ),
                  const Text(
                    'موقعیت',
                    style: TextStyle(color: AppTheme.muted, fontSize: 10),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  formatMoney(total),
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    color: AppTheme.title,
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  top == null
                      ? '—'
                      : 'بزرگ‌ترین سهم: ${top.label} ${_plainPct(concentration)}',
                  textAlign: TextAlign.right,
                  style: const TextStyle(color: AppTheme.muted, fontSize: 11),
                ),
                if (concentrated) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                    decoration: BoxDecoration(
                      color: AppTheme.negative.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: AppTheme.negative.withValues(alpha: 0.35),
                      ),
                    ),
                    child: const Text(
                      'تمرکز بالا روی یک نام',
                      style: TextStyle(
                        color: AppTheme.negative,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _KindBreakdown extends StatelessWidget {
  const _KindBreakdown({required this.holdings});

  final List<({Asset asset, HoldingMetrics metrics})> holdings;

  @override
  Widget build(BuildContext context) {
    final total =
        holdings.fold<double>(0, (s, h) => s + h.metrics.marketValue);
    final byKind = <AssetKind, double>{};
    for (final h in holdings) {
      final kind = detectAssetKind(
        name: h.asset.name,
        symbol: h.asset.symbol,
        notes: h.asset.notes,
      );
      byKind[kind] = (byKind[kind] ?? 0) + h.metrics.marketValue;
    }
    final rows = byKind.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    if (rows.isEmpty) return const SizedBox.shrink();

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0)
              const Divider(height: 1, color: AppTheme.border),
            _KindRow(
              kind: rows[i].key,
              value: rows[i].value,
              share: total <= 0 ? 0 : rows[i].value / total,
            ),
          ],
        ],
      ),
    );
  }
}

class _KindRow extends StatelessWidget {
  const _KindRow({
    required this.kind,
    required this.value,
    required this.share,
  });

  final AssetKind kind;
  final double value;
  final double share;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 11, 14, 11),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  formatCompactToman(value),
                  style: const TextStyle(
                    color: AppTheme.title,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: share.clamp(0.0, 1.0),
                    minHeight: 4,
                    backgroundColor: AppTheme.border,
                    color: kind.color,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            _plainPct(share * 100),
            style: const TextStyle(
              color: AppTheme.muted,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(
              color: kind.color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(kind.icon, size: 14, color: kind.color),
                const SizedBox(width: 5),
                Text(
                  kind.label,
                  style: TextStyle(
                    color: kind.color,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HoldingLedgerRow extends StatelessWidget {
  const _HoldingLedgerRow({
    required this.asset,
    required this.metrics,
    required this.totalValue,
    required this.usdt,
    required this.canMutate,
  });

  final Asset asset;
  final HoldingMetrics metrics;
  final double totalValue;
  final double? usdt;
  final bool canMutate;

  @override
  Widget build(BuildContext context) {
    final kind = detectAssetKind(
      name: asset.name,
      symbol: asset.symbol,
      notes: asset.notes,
    );
    final share =
        totalValue <= 0 ? 0.0 : metrics.marketValue / totalValue;
    final usdValue = metrics.marketValueUsd(usdt);
    final usdPnl = metrics.unrealizedPnlUsd(usdt);
    final tone =
        metrics.unrealizedPnl >= 0 ? AppTheme.positive : AppTheme.negative;
    final qtyDecimals =
        (metrics.quantity - metrics.quantity.roundToDouble()).abs() < 1e-9
            ? 0
            : 4;
    final qtyNumber = formatNumber(metrics.quantity, decimals: qtyDecimals);
    final unit = kind.unitLabel.isNotEmpty
        ? kind.unitLabel
        : (asset.symbol.trim().isEmpty ? '' : asset.symbol.trim());
    final qtyLabel = unit.isEmpty ? qtyNumber : '$qtyNumber $unit';

    return Material(
      color: AppTheme.card,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => openAssetDetail(context, asset: asset),
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppTheme.border),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 16,
                    backgroundColor: kind.color.withValues(alpha: 0.18),
                    child: Icon(kind.icon, color: kind.color, size: 17),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          asset.name,
                          textAlign: TextAlign.right,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppTheme.title,
                            fontWeight: FontWeight.w800,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '$qtyLabel · ${_plainPct(share * 100)} از دفتر',
                          textAlign: TextAlign.right,
                          style: const TextStyle(
                            color: AppTheme.muted,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (asset.id != null)
                    ProfitAlertBell(
                      id: ProfitAlert.forAsset(asset.id!),
                      name: asset.name,
                      symbol: asset.symbol,
                      currentPnl: metrics.unrealizedPnl,
                      currentPnlPct: metrics.unrealizedPnlPct,
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
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: share.clamp(0.0, 1.0),
                  minHeight: 3,
                  backgroundColor: AppTheme.border,
                  color: kind.color,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _MiniCell(
                      label: 'ارزش',
                      value: usdValue != null
                          ? formatUsd(usdValue, compact: true)
                          : formatCompactToman(metrics.marketValue),
                      sub: usdValue != null
                          ? formatCompactToman(metrics.marketValue)
                          : null,
                      tone: AppTheme.title,
                    ),
                  ),
                  Expanded(
                    child: _MiniCell(
                      label: 'سود شناور',
                      value: formatCompactToman(
                        metrics.unrealizedPnl,
                        showSign: true,
                      ),
                      sub: formatPct(metrics.unrealizedPnlPct),
                      tone: tone,
                    ),
                  ),
                  Expanded(
                    child: _MiniCell(
                      label: usdPnl == null ? 'میانگین خرید' : 'سود دلاری',
                      value: usdPnl == null
                          ? formatTomanPrice(metrics.avgBuyPrice)
                          : formatUsd(usdPnl, compact: true, showSign: true),
                      sub: usdPnl == null
                          ? null
                          : formatPct(metrics.unrealizedPnlUsdPct(usdt)),
                      tone: usdPnl == null
                          ? AppTheme.muted
                          : (usdPnl >= 0
                              ? AppTheme.positive
                              : AppTheme.negative),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MiniCell extends StatelessWidget {
  const _MiniCell({
    required this.label,
    required this.value,
    required this.tone,
    this.sub,
  });

  final String label;
  final String value;
  final String? sub;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          label,
          style: const TextStyle(color: AppTheme.muted, fontSize: 10),
        ),
        const SizedBox(height: 3),
        Text(
          value,
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: tone,
            fontSize: 12,
            fontWeight: FontWeight.w800,
          ),
        ),
        if (sub != null) ...[
          const SizedBox(height: 2),
          Text(
            sub!,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: tone == AppTheme.title ? AppTheme.muted : tone,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ],
    );
  }
}

class _Footnote extends StatelessWidget {
  const _Footnote({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      textAlign: TextAlign.right,
      style: const TextStyle(
        color: AppTheme.muted,
        fontSize: 11,
        height: 1.45,
      ),
    );
  }
}

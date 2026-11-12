import 'package:flutter/material.dart';
import 'package:invest/domain/models/asset.dart';
import 'package:invest/domain/models/asset_kind.dart';
import 'package:invest/domain/models/trade.dart';
import 'package:invest/domain/utils/money.dart';
import 'package:invest/state/app_state.dart';
import 'package:invest/ui/layout/page_padding.dart';
import 'package:invest/ui/pages/assets_page.dart';
import 'package:invest/ui/pages/trades_page.dart';
import 'package:invest/ui/theme/app_theme.dart';
import 'package:provider/provider.dart';

/// Cohesive and unified Trades Hub under the bottom-nav «معاملات» tab.
/// Integrates:
/// 1. Open Positions (معاملات باز) with live PnL, quick-sell, edit, filters & search.
/// 2. Closed Trades History (معاملات بسته) with realized profits, win-rate & audit.
/// 3. Portfolio Allocation & Ledger (سبد دارایی‌ها) with donut & holdings breakdown.
class TradesHubPage extends StatefulWidget {
  const TradesHubPage({super.key});

  @override
  State<TradesHubPage> createState() => _TradesHubPageState();
}

class _TradesHubPageState extends State<TradesHubPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  int _activeTab = 0; // 0: Open, 1: Closed, 2: Assets / Allocation

  AssetKind? _selectedKind;
  String _searchQuery = '';
  String _sortModeOpen = 'date_desc'; // date_desc, date_asc, pnl_desc, value_desc
  String _sortModeClosed = 'sell_desc'; // sell_desc, pnl_desc

  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) return;
      if (_tabController.index != _activeTab) {
        setState(() => _activeTab = _tabController.index);
      }
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _tabController.dispose();
    super.dispose();
  }

  Asset? _findAsset(List<Asset> assets, int? id) {
    if (id == null) return null;
    for (final a in assets) {
      if (a.id == id) return a;
    }
    return null;
  }

  AssetKind _tradeKind(Trade trade, List<Asset> assets) {
    final a = _findAsset(assets, trade.assetId);
    if (a != null) {
      return detectAssetKind(name: a.name, symbol: a.symbol, notes: a.notes);
    }
    return detectAssetKind(name: trade.assetName, symbol: trade.assetSymbol);
  }

  List<Trade> _filterOpen(List<Trade> raw, List<Asset> assets) {
    final active = raw.where((t) => t.quantity > 1e-9).toList();
    var filtered = active;
    if (_selectedKind != null) {
      filtered = filtered
          .where((t) => _tradeKind(t, assets) == _selectedKind)
          .toList();
    }
    if (_searchQuery.trim().isNotEmpty) {
      final q = _searchQuery.trim().toLowerCase();
      filtered = filtered.where((t) {
        final name = (t.assetName ?? '').toLowerCase();
        final sym = (t.assetSymbol ?? '').toLowerCase();
        return name.contains(q) || sym.contains(q);
      }).toList();
    }
    switch (_sortModeOpen) {
      case 'date_asc':
        filtered.sort((a, b) => a.buyDate.compareTo(b.buyDate));
        break;
      case 'pnl_desc':
        filtered.sort((a, b) => b.unrealizedPnl.compareTo(a.unrealizedPnl));
        break;
      case 'value_desc':
        filtered.sort((a, b) => b.currentValue.compareTo(a.currentValue));
        break;
      case 'date_desc':
      default:
        filtered.sort((a, b) => b.buyDate.compareTo(a.buyDate));
        break;
    }
    return filtered;
  }

  List<Trade> _filterClosed(List<Trade> raw, List<Asset> assets) {
    var filtered = List<Trade>.from(raw);
    if (_selectedKind != null) {
      filtered = filtered
          .where((t) => _tradeKind(t, assets) == _selectedKind)
          .toList();
    }
    if (_searchQuery.trim().isNotEmpty) {
      final q = _searchQuery.trim().toLowerCase();
      filtered = filtered.where((t) {
        final name = (t.assetName ?? '').toLowerCase();
        final sym = (t.assetSymbol ?? '').toLowerCase();
        return name.contains(q) || sym.contains(q);
      }).toList();
    }
    switch (_sortModeClosed) {
      case 'pnl_desc':
        filtered.sort((a, b) =>
            (b.realizedPnl ?? 0).compareTo(a.realizedPnl ?? 0));
        break;
      case 'sell_desc':
      default:
        filtered.sort((a, b) {
          final sa = a.sellDate ?? '';
          final sb = b.sellDate ?? '';
          final c = sb.compareTo(sa);
          return c != 0 ? c : b.buyDate.compareTo(a.buyDate);
        });
        break;
    }
    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final openTrades = state.openTrades.where((t) => t.quantity > 1e-9).toList();
    final closedTrades = state.closedTrades;
    final assets = state.assets;

    return NestedScrollView(
      headerSliverBuilder: (context, innerBoxIsScrolled) {
        return [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _StatusHeader(
                    offline: state.offline,
                    openCount: openTrades.length,
                    closedCount: closedTrades.length,
                    assetCount: assets.length,
                  ),
                  const SizedBox(height: 10),
                  _SummaryBanner(
                    tab: _activeTab,
                    openTrades: openTrades,
                    closedTrades: closedTrades,
                    assets: assets,
                  ),
                  const SizedBox(height: 12),
                  _SegmentSelector(
                    activeTab: _activeTab,
                    openCount: openTrades.length,
                    closedCount: closedTrades.length,
                    assetCount: assets.length,
                    onTabSelected: (index) {
                      setState(() => _activeTab = index);
                      _tabController.animateTo(index);
                    },
                  ),
                  if (_activeTab < 2) ...[
                    const SizedBox(height: 10),
                    _FilterAndSearchRow(
                      selectedKind: _selectedKind,
                      searchCtrl: _searchCtrl,
                      sortMode: _activeTab == 0 ? _sortModeOpen : _sortModeClosed,
                      isOpenTab: _activeTab == 0,
                      onKindChanged: (kind) => setState(() => _selectedKind = kind),
                      onSearchChanged: (q) => setState(() => _searchQuery = q),
                      onSortChanged: (s) => setState(() {
                        if (_activeTab == 0) {
                          _sortModeOpen = s;
                        } else {
                          _sortModeClosed = s;
                        }
                      }),
                    ),
                  ],
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
        ];
      },
      body: TabBarView(
        controller: _tabController,
        physics: const NeverScrollableScrollPhysics(), // tab switching via buttons
        children: [
          // Tab 0: Open Positions
          _OpenTradesList(
            trades: _filterOpen(state.openTrades, assets),
            canMutate: state.canMutate,
            onRefresh: () => state.refreshAll(),
          ),
          // Tab 1: Closed Trades
          _ClosedTradesList(
            trades: _filterClosed(state.closedTrades, assets),
            canMutate: state.canMutate,
            onRefresh: () => state.refreshAll(),
          ),
          // Tab 2: Holdings & Allocation Desk
          const AssetsPage(),
        ],
      ),
    );
  }
}

class _StatusHeader extends StatelessWidget {
  const _StatusHeader({
    required this.offline,
    required this.openCount,
    required this.closedCount,
    required this.assetCount,
  });

  final bool offline;
  final int openCount;
  final int closedCount;
  final int assetCount;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(
          Icons.swap_horiz_rounded,
          size: 15,
          color: AppTheme.accent,
        ),
        const SizedBox(width: 6),
        const Text(
          'میز جامع معاملات',
          style: TextStyle(
            color: AppTheme.title,
            fontSize: 12,
            fontWeight: FontWeight.w800,
          ),
        ),
        const Spacer(),
        Text(
          '$openCount موقعیت باز · $closedCount بسته · $assetCount دارایی',
          style: const TextStyle(
            color: AppTheme.muted,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _SummaryBanner extends StatelessWidget {
  const _SummaryBanner({
    required this.tab,
    required this.openTrades,
    required this.closedTrades,
    required this.assets,
  });

  final int tab;
  final List<Trade> openTrades;
  final List<Trade> closedTrades;
  final List<Asset> assets;

  @override
  Widget build(BuildContext context) {
    if (tab == 0) {
      // Open Positions Stats
      final openValue =
          openTrades.fold<double>(0, (s, t) => s + t.currentValue);
      final openCost = openTrades.fold<double>(0, (s, t) => s + t.buyCost);
      final openPnl = openValue - openCost;
      final openPct = openCost > 0 ? (openPnl / openCost * 100) : 0.0;
      final isUp = openPnl >= 0;
      final pnlTone = isUp ? AppTheme.positive : AppTheme.negative;

      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppTheme.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.border),
        ),
        child: Row(
          children: [
            Expanded(
              child: _MetricCell(
                title: 'ارزش موقعیت‌ها',
                value: formatMoney(openValue),
                color: AppTheme.title,
              ),
            ),
            Container(width: 1, height: 32, color: AppTheme.border),
            Expanded(
              child: _MetricCell(
                title: 'سود/زیان باز',
                value: formatMoney(openPnl, showSign: true),
                sub: '${formatNumber(openPct.abs(), decimals: 1)}٪',
                color: pnlTone,
              ),
            ),
            Container(width: 1, height: 32, color: AppTheme.border),
            Expanded(
              child: _MetricCell(
                title: 'تعداد موقعیت',
                value: '${openTrades.length} معامله',
                color: AppTheme.muted,
              ),
            ),
          ],
        ),
      );
    } else if (tab == 1) {
      // Closed Trades Stats
      final closedPnl =
          closedTrades.fold<double>(0, (s, t) => s + (t.realizedPnl ?? 0));
      final wins = closedTrades.where((t) => (t.realizedPnl ?? 0) > 0).length;
      final winRate =
          closedTrades.isNotEmpty ? (wins / closedTrades.length * 100) : 0.0;
      final isUp = closedPnl >= 0;
      final pnlTone = isUp ? AppTheme.positive : AppTheme.negative;

      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppTheme.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.border),
        ),
        child: Row(
          children: [
            Expanded(
              child: _MetricCell(
                title: 'سود محقق‌شده کل',
                value: formatMoney(closedPnl, showSign: true),
                color: pnlTone,
              ),
            ),
            Container(width: 1, height: 32, color: AppTheme.border),
            Expanded(
              child: _MetricCell(
                title: 'نرخ سوددهی',
                value: '${winRate.toStringAsFixed(0)}٪',
                sub: '$wins از ${closedTrades.length}',
                color: winRate >= 50 ? AppTheme.positive : AppTheme.negative,
              ),
            ),
            Container(width: 1, height: 32, color: AppTheme.border),
            Expanded(
              child: _MetricCell(
                title: 'کل فروش‌ها',
                value: '${closedTrades.length} معامله',
                color: AppTheme.muted,
              ),
            ),
          ],
        ),
      );
    } else {
      // Holdings / Allocation summary
      final totalValue = assets.fold<double>(0, (s, a) => s + a.marketValue);
      final totalPnl = assets.fold<double>(0, (s, a) => s + a.unrealizedPnl);
      final isUp = totalPnl >= 0;

      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppTheme.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.border),
        ),
        child: Row(
          children: [
            Expanded(
              child: _MetricCell(
                title: 'ارزش پورتفو',
                value: formatMoney(totalValue),
                color: AppTheme.title,
              ),
            ),
            Container(width: 1, height: 32, color: AppTheme.border),
            Expanded(
              child: _MetricCell(
                title: 'سود کل دارایی',
                value: formatMoney(totalPnl, showSign: true),
                color: isUp ? AppTheme.positive : AppTheme.negative,
              ),
            ),
            Container(width: 1, height: 32, color: AppTheme.border),
            Expanded(
              child: _MetricCell(
                title: 'تعداد دارایی',
                value: '${assets.length} قلم',
                color: AppTheme.muted,
              ),
            ),
          ],
        ),
      );
    }
  }
}

class _MetricCell extends StatelessWidget {
  const _MetricCell({
    required this.title,
    required this.value,
    this.sub,
    required this.color,
  });

  final String title;
  final String value;
  final String? sub;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: AppTheme.muted,
            fontSize: 10,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: color,
            fontSize: 12,
            fontWeight: FontWeight.w800,
          ),
        ),
        if (sub != null) ...[
          const SizedBox(height: 1),
          Text(
            sub!,
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ],
    );
  }
}

class _SegmentSelector extends StatelessWidget {
  const _SegmentSelector({
    required this.activeTab,
    required this.openCount,
    required this.closedCount,
    required this.assetCount,
    required this.onTabSelected,
  });

  final int activeTab;
  final int openCount;
  final int closedCount;
  final int assetCount;
  final ValueChanged<int> onTabSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: _TabButton(
              label: 'موقعیت‌های باز',
              count: openCount,
              isSelected: activeTab == 0,
              onTap: () => onTabSelected(0),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: _TabButton(
              label: 'معاملات بسته',
              count: closedCount,
              isSelected: activeTab == 1,
              onTap: () => onTabSelected(1),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: _TabButton(
              label: 'سبد دارایی‌ها',
              count: assetCount,
              isSelected: activeTab == 2,
              onTap: () => onTabSelected(2),
            ),
          ),
        ],
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  const _TabButton({
    required this.label,
    required this.count,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final int count;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(11),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.accent : Colors.transparent,
          borderRadius: BorderRadius.circular(11),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : AppTheme.muted,
                fontSize: 11.5,
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
              ),
            ),
            const SizedBox(width: 5),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: isSelected
                    ? Colors.white.withOpacity(0.2)
                    : AppTheme.border.withOpacity(0.4),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  color: isSelected ? Colors.white : AppTheme.muted,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterAndSearchRow extends StatelessWidget {
  const _FilterAndSearchRow({
    required this.selectedKind,
    required this.searchCtrl,
    required this.sortMode,
    required this.isOpenTab,
    required this.onKindChanged,
    required this.onSearchChanged,
    required this.onSortChanged,
  });

  final AssetKind? selectedKind;
  final TextEditingController searchCtrl;
  final String sortMode;
  final bool isOpenTab;
  final ValueChanged<AssetKind?> onKindChanged;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<String> onSortChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Search and Sort Row
        Row(
          children: [
            Expanded(
              child: Container(
                height: 36,
                decoration: BoxDecoration(
                  color: AppTheme.surface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppTheme.border),
                ),
                child: TextField(
                  controller: searchCtrl,
                  onChanged: onSearchChanged,
                  style: const TextStyle(fontSize: 12, color: AppTheme.title),
                  textAlignVertical: TextAlignVertical.center,
                  decoration: InputDecoration(
                    hintText: 'جستجوی نام یا نماد معامله...',
                    hintStyle:
                        const TextStyle(fontSize: 11, color: AppTheme.muted),
                    prefixIcon: const Icon(Icons.search_rounded,
                        size: 16, color: AppTheme.muted),
                    suffixIcon: searchCtrl.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear_rounded, size: 14),
                            onPressed: () {
                              searchCtrl.clear();
                              onSearchChanged('');
                            },
                          )
                        : null,
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            // Sort Dropdown
            Container(
              height: 36,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: AppTheme.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.border),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: sortMode,
                  icon: const Icon(Icons.sort_rounded,
                      size: 16, color: AppTheme.accent),
                  style: const TextStyle(
                      color: AppTheme.title,
                      fontSize: 11,
                      fontWeight: FontWeight.w700),
                  dropdownColor: AppTheme.surface,
                  items: isOpenTab
                      ? const [
                          DropdownMenuItem(
                              value: 'date_desc', child: Text('جدیدترین خرید')),
                          DropdownMenuItem(
                              value: 'pnl_desc', child: Text('بیشترین سود')),
                          DropdownMenuItem(
                              value: 'value_desc', child: Text('بیشترین ارزش')),
                          DropdownMenuItem(
                              value: 'date_asc', child: Text('قدیمی‌ترین خرید')),
                        ]
                      : const [
                          DropdownMenuItem(
                              value: 'sell_desc', child: Text('جدیدترین فروش')),
                          DropdownMenuItem(
                              value: 'pnl_desc', child: Text('بیشترین سود')),
                        ],
                  onChanged: (v) {
                    if (v != null) onSortChanged(v);
                  },
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        // Kind Filter Chips
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _KindChip(
                label: 'همه',
                isSelected: selectedKind == null,
                onTap: () => onKindChanged(null),
              ),
              const SizedBox(width: 6),
              _KindChip(
                label: 'ارز دیجیتال',
                isSelected: selectedKind == AssetKind.crypto,
                onTap: () => onKindChanged(AssetKind.crypto),
              ),
              const SizedBox(width: 6),
              _KindChip(
                label: 'طلا و سکه',
                isSelected: selectedKind == AssetKind.gold,
                onTap: () => onKindChanged(AssetKind.gold),
              ),
              const SizedBox(width: 6),
              _KindChip(
                label: 'ارز',
                isSelected: selectedKind == AssetKind.currency,
                onTap: () => onKindChanged(AssetKind.currency),
              ),
              const SizedBox(width: 6),
              _KindChip(
                label: 'سهام و صندوق',
                isSelected: selectedKind == AssetKind.stock,
                onTap: () => onKindChanged(AssetKind.stock),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _KindChip extends StatelessWidget {
  const _KindChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected
              ? AppTheme.accent.withOpacity(0.15)
              : AppTheme.card,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? AppTheme.accent : AppTheme.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? AppTheme.accent : AppTheme.muted,
            fontSize: 10.5,
            fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _OpenTradesList extends StatelessWidget {
  const _OpenTradesList({
    required this.trades,
    required this.canMutate,
    required this.onRefresh,
  });

  final List<Trade> trades;
  final bool canMutate;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    if (trades.isEmpty) {
      return RefreshIndicator(
        onRefresh: onRefresh,
        child: ListView(
          padding: shellPagePadding(extraForFab: canMutate),
          children: [
            const SizedBox(height: 40),
            Center(
              child: Column(
                children: [
                  Icon(
                    Icons.inventory_2_outlined,
                    size: 48,
                    color: AppTheme.muted.withOpacity(0.6),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'موقعیت باز فعالی یافت نشد',
                    style: TextStyle(
                      color: AppTheme.title,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'می‌توانید با دکمه زیر معامله خرید جدید ثبت کنید.',
                    style: TextStyle(
                      color: AppTheme.muted,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 18),
                  if (canMutate)
                    ElevatedButton.icon(
                      onPressed: () => showBuyTradeDialog(context),
                      icon: const Icon(Icons.add_shopping_cart_rounded, size: 16),
                      label: const Text('ثبت معامله خرید جدید'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.accent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView.separated(
        padding: shellPagePadding(extraForFab: canMutate),
        itemCount: trades.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, i) {
          final t = trades[i];
          return TradeTile(
            trade: t,
            open: true,
            showAssetIdentity: true,
            onSell: canMutate ? () => showSellTradeDialog(context, t) : null,
            onEdit: canMutate ? () => showEditOpenTradeDialog(context, t) : null,
          );
        },
      ),
    );
  }
}

class _ClosedTradesList extends StatelessWidget {
  const _ClosedTradesList({
    required this.trades,
    required this.canMutate,
    required this.onRefresh,
  });

  final List<Trade> trades;
  final bool canMutate;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    if (trades.isEmpty) {
      return RefreshIndicator(
        onRefresh: onRefresh,
        child: ListView(
          padding: shellPagePadding(extraForFab: canMutate),
          children: [
            const SizedBox(height: 40),
            Center(
              child: Column(
                children: [
                  Icon(
                    Icons.history_toggle_off_rounded,
                    size: 48,
                    color: AppTheme.muted.withOpacity(0.6),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'معامله بسته‌شده‌ای ثبت نشده است',
                    style: TextStyle(
                      color: AppTheme.title,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'با فروش و تسویه معاملات باز، سوابق و سود تحقق‌یافته اینجا درج می‌شود.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppTheme.muted,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView.separated(
        padding: shellPagePadding(extraForFab: canMutate),
        itemCount: trades.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, i) {
          final t = trades[i];
          return TradeTile(
            trade: t,
            open: false,
            showAssetIdentity: true,
            onDelete: canMutate ? () => confirmDeleteClosedTrade(context, t) : null,
          );
        },
      ),
    );
  }
}

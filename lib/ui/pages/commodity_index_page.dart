import 'package:flutter/material.dart';
import 'package:invest/domain/models/commodity_quote.dart';
import 'package:invest/domain/services/index_analytics.dart';
import 'package:invest/domain/utils/dates.dart';
import 'package:invest/state/app_state.dart';
import 'package:invest/ui/layout/page_padding.dart';
import 'package:invest/ui/pages/iran_inflation_pane.dart';
import 'package:invest/ui/pages/quote_detail_page.dart';
import 'package:invest/ui/theme/app_theme.dart';
import 'package:invest/ui/widgets/index_quote_card.dart';
import 'package:provider/provider.dart';

class CommodityIndexPage extends StatefulWidget {
  const CommodityIndexPage({super.key});

  @override
  State<CommodityIndexPage> createState() => _CommodityIndexPageState();
}

class _CommodityIndexPageState extends State<CommodityIndexPage> {
  late final PageController _pageController;
  final _searchCtrl = TextEditingController();
  int _page = 0;
  String _query = '';
  WallexSort _wallexSort = WallexSort.volume;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final state = context.read<AppState>();
      if (state.commodityIndex.isEmpty &&
          state.wallexMarkets.isEmpty &&
          !state.commodityIndexLoading) {
        state.refreshCommodityIndex(force: true);
      }
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  List<CommodityQuote> _wallexQuotes(List<CommodityQuote> source) {
    final q = _query.trim().toLowerCase();
    final filtered = q.isEmpty
        ? source
        : source
            .where(
              (e) =>
                  e.name.toLowerCase().contains(q) ||
                  e.symbol.toLowerCase().contains(q) ||
                  (e.marketSymbol?.toLowerCase().contains(q) ?? false),
            )
            .toList();
    return sortWallexQuotes(filtered, _wallexSort);
  }

  void _goToPage(int i) {
    if (i == _page) return;
    setState(() => _page = i);
    if (!_pageController.hasClients) return;
    _pageController.animateToPage(
      i,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final offlineHint = state.offline ||
        (state.commodityIndexError?.contains('آفلاین') ?? false);
    final wallex = _wallexQuotes(state.wallexMarkets);
    final essentialsPulse = marketPulse(
      state.commodityIndex,
      marketLabel: 'بازار',
    );
    final wallexPulse = marketPulse(
      state.wallexMarkets,
      marketLabel: 'دفتر والکس',
    );
    final anchors = indexAnchors(state.commodityIndex);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: _IndexHeader(
            updatedAt: _page == 2
                ? state.iranInflation?.fetchedAt
                : state.commodityIndexUpdatedAt,
            offlineHint: offlineHint ||
                (state.iranInflationError?.contains('آفلاین') ?? false),
            page: _page,
            wallexCount: state.wallexMarkets.length,
            inflationPeriod: state.iranInflation?.periodLabel,
            calendar: state.settings.calendar,
            pulse: _page == 1 ? wallexPulse : essentialsPulse,
            anchors: anchors,
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: _SegmentTabs(
            index: _page,
            onChanged: _goToPage,
          ),
        ),
        if (_page == 1) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              controller: _searchCtrl,
              textAlign: TextAlign.right,
              onChanged: (v) => setState(() => _query = v),
              decoration: InputDecoration(
                hintText: 'جستجوی ارز در والکس…',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear_rounded),
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() => _query = '');
                        },
                      ),
                isDense: true,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: _WallexSortChips(
              value: _wallexSort,
              onChanged: (v) => setState(() => _wallexSort = v),
            ),
          ),
        ],
        if (state.commodityIndexError != null &&
            state.commodityIndex.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              state.commodityIndexError!,
              textAlign: TextAlign.right,
              style: const TextStyle(color: AppTheme.muted, fontSize: 11),
            ),
          ),
        Expanded(
          child: PageView(
            controller: _pageController,
            onPageChanged: (i) {
              setState(() => _page = i);
            },
            children: [
              _EssentialsPane(
                loading:
                    state.commodityIndexLoading && state.commodityIndex.isEmpty,
                emptyMessage: state.commodityIndexError ?? 'داده‌ای دریافت نشد',
                onRetry: () =>
                    context.read<AppState>().refreshCommodityIndex(force: true),
                onRefresh: () =>
                    context.read<AppState>().refreshCommodityIndex(force: true),
                quotes: state.commodityIndex,
              ),
              _QuoteListPane(
                loading:
                    state.commodityIndexLoading && state.wallexMarkets.isEmpty,
                emptyMessage: state.wallexMarkets.isEmpty
                    ? (state.commodityIndexError ?? 'بازار والکس در دسترس نیست')
                    : 'نتیجه‌ای برای «$_query» پیدا نشد',
                onRetry: state.wallexMarkets.isEmpty
                    ? () => context
                        .read<AppState>()
                        .refreshCommodityIndex(force: true)
                    : () async {
                        _searchCtrl.clear();
                        setState(() => _query = '');
                      },
                onRefresh: () =>
                    context.read<AppState>().refreshCommodityIndex(force: true),
                quotes: wallex,
                emptyIcon: Icons.currency_exchange_rounded,
                showVolume: true,
                showRole: false,
                retryLabel: state.wallexMarkets.isEmpty || _query.isEmpty
                    ? 'تلاش مجدد'
                    : 'پاک کردن جستجو',
              ),
              const IranInflationPane(),
            ],
          ),
        ),
      ],
    );
  }
}

class _SegmentTabs extends StatelessWidget {
  const _SegmentTabs({required this.index, required this.onChanged});

  final int index;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: _TabChip(
              label: 'بازار',
              selected: index == 0,
              onTap: () => onChanged(0),
            ),
          ),
          Expanded(
            child: _TabChip(
              label: 'والکس',
              selected: index == 1,
              onTap: () => onChanged(1),
            ),
          ),
          Expanded(
            child: _TabChip(
              label: 'تورم',
              selected: index == 2,
              onTap: () => onChanged(2),
            ),
          ),
        ],
      ),
    );
  }
}

class _TabChip extends StatelessWidget {
  const _TabChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppTheme.accent : Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: selected ? Colors.white : AppTheme.muted,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }
}

class _WallexSortChips extends StatelessWidget {
  const _WallexSortChips({required this.value, required this.onChanged});

  final WallexSort value;
  final ValueChanged<WallexSort> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget chip(WallexSort sort, String label) {
      final on = value == sort;
      return Expanded(
        child: Material(
          color: on ? AppTheme.accent.withValues(alpha: 0.85) : AppTheme.card,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            onTap: () => onChanged(sort),
            borderRadius: BorderRadius.circular(10),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: on ? AppTheme.accent : AppTheme.border,
                ),
              ),
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: on ? Colors.white : AppTheme.muted,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        chip(WallexSort.volume, 'حجم'),
        const SizedBox(width: 8),
        chip(WallexSort.gainers, 'صعودی'),
        const SizedBox(width: 8),
        chip(WallexSort.losers, 'نزولی'),
      ],
    );
  }
}

class _IndexHeader extends StatelessWidget {
  const _IndexHeader({
    this.updatedAt,
    this.offlineHint = false,
    required this.page,
    required this.wallexCount,
    this.inflationPeriod,
    this.calendar = 'jalali',
    required this.pulse,
    required this.anchors,
  });

  final DateTime? updatedAt;
  final bool offlineHint;
  final int page;
  final int wallexCount;
  final String? inflationPeriod;
  final String calendar;
  final MarketPulse pulse;
  final IndexAnchors anchors;

  @override
  Widget build(BuildContext context) {
    final inflation = page == 2;
    final title = switch (page) {
      1 => 'دفتر والکس',
      2 => 'تورم رسمی',
      _ => 'نبض بازار',
    };
    final subtitle = offlineHint
        ? 'نمایش داده‌های ذخیره‌شده — اتصال اینترنت برای بروزرسانی'
        : switch (page) {
            1 => pulse.isEmpty
                ? '$wallexCount بازار تومان — مرتب‌سازی حجم، صعود و نزول'
                : pulse.headline,
            2 => inflationPeriod == null
                ? 'شاخص قیمت مصرف‌کننده مرکز آمار — سبد خانوار، نه قیمت طلا'
                : 'CPI مرکز آمار · $inflationPeriod — سبد مصرف، نه دارایی',
            _ => pulse.isEmpty
                ? 'دلار آزاد، طلای ۱۸ عیار و دارایی‌های ریسکی'
                : pulse.headline,
          };

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: inflation
              ? const [Color(0xFF3D1A1A), Color(0xFF241212)]
              : pulse.isRed
                  ? const [Color(0xFF3A1E1E), Color(0xFF1A241C)]
                  : const [Color(0xFF1A3D2E), Color(0xFF122820)],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Row(
            children: [
              _PageDots(active: page, alert: inflation),
              const Spacer(),
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                switch (page) {
                  1 => Icons.currency_exchange_rounded,
                  2 => Icons.trending_up_rounded,
                  _ => Icons.monitor_heart_outlined,
                },
                color: inflation
                    ? const Color(0xFFFF8A80)
                    : pulse.isRed
                        ? AppTheme.negative
                        : AppTheme.positive,
                size: 22,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            textAlign: TextAlign.right,
            style: TextStyle(
              color:
                  inflation ? const Color(0xFFD7B0B0) : const Color(0xFFB8D4C6),
              fontSize: 12,
              height: 1.45,
            ),
          ),
          if (!inflation && !pulse.isEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              alignment: WrapAlignment.end,
              children: [
                _PulseChip(
                  label: '${pulse.up} سبز',
                  color: AppTheme.positive,
                ),
                _PulseChip(
                  label: '${pulse.down} قرمز',
                  color: AppTheme.negative,
                ),
                if (pulse.flat > 0)
                  _PulseChip(
                    label: '${pulse.flat} بدون تغییر',
                    color: const Color(0xFFB8D4C6),
                  ),
              ],
            ),
          ],
          if (page == 0 && anchors.caption != null) ...[
            const SizedBox(height: 10),
            Text(
              anchors.caption!,
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: Color(0xFFD5E8DC),
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          if (updatedAt != null) ...[
            const SizedBox(height: 10),
            Text(
              'آخرین بروزرسانی: ${_formatUpdatedAt(updatedAt!, calendar)}',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 11,
              ),
            ),
          ],
        ],
      ),
    );
  }

  static String _formatUpdatedAt(DateTime dt, String calendar) {
    final local = dt.toLocal();
    final h = local.hour.toString().padLeft(2, '0');
    final m = local.minute.toString().padLeft(2, '0');
    final now = DateTime.now();
    final sameDay = local.year == now.year &&
        local.month == now.month &&
        local.day == now.day;
    if (sameDay) return '$h:$m';
    return '${formatDisplayDate(toIsoDate(local), calendar)} $h:$m';
  }
}

class _PulseChip extends StatelessWidget {
  const _PulseChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _PageDots extends StatelessWidget {
  const _PageDots({required this.active, this.alert = false});

  final int active;
  final bool alert;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(3, (i) {
        final on = i == active;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsetsDirectional.only(end: 6),
          width: on ? 18 : 7,
          height: 7,
          decoration: BoxDecoration(
            color: on
                ? (alert ? const Color(0xFFFF8A80) : AppTheme.positive)
                : Colors.white.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(8),
          ),
        );
      }),
    );
  }
}

class _EssentialsPane extends StatelessWidget {
  const _EssentialsPane({
    required this.loading,
    required this.emptyMessage,
    required this.onRetry,
    required this.onRefresh,
    required this.quotes,
  });

  final bool loading;
  final String emptyMessage;
  final Future<void> Function() onRetry;
  final Future<void> Function() onRefresh;
  final List<CommodityQuote> quotes;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return RefreshIndicator(
        onRefresh: onRefresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: const [
            SizedBox(height: 120),
            Center(child: CircularProgressIndicator()),
          ],
        ),
      );
    }

    if (quotes.isEmpty) {
      return RefreshIndicator(
        onRefresh: onRefresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: shellPagePadding(),
          children: [
            const SizedBox(height: 48),
            const Icon(Icons.insights_outlined,
                size: 40, color: AppTheme.muted),
            const SizedBox(height: 12),
            Text(
              emptyMessage,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppTheme.muted),
            ),
            const SizedBox(height: 12),
            Center(
              child: OutlinedButton(
                onPressed: onRetry,
                child: const Text('تلاش مجدد'),
              ),
            ),
          ],
        ),
      );
    }

    final groups = groupEssentials(quotes);
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: shellPagePadding(),
        itemCount: groups.length,
        itemBuilder: (context, gi) {
          final group = groups[gi];
          return Padding(
            padding: EdgeInsets.only(bottom: gi == groups.length - 1 ? 0 : 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  group.spec.title,
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    color: AppTheme.title,
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  group.spec.caption,
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    color: AppTheme.muted,
                    fontSize: 11,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 10),
                for (var i = 0; i < group.quotes.length; i++) ...[
                  if (i > 0) const SizedBox(height: 10),
                  IndexQuoteCard(
                    quote: group.quotes[i],
                    onTap: () => openQuoteDetail(context, group.quotes[i]),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _QuoteListPane extends StatelessWidget {
  const _QuoteListPane({
    required this.loading,
    required this.emptyMessage,
    required this.onRetry,
    required this.onRefresh,
    required this.quotes,
    required this.emptyIcon,
    this.showVolume = false,
    this.showRole = true,
    this.retryLabel = 'تلاش مجدد',
  });

  final bool loading;
  final String emptyMessage;
  final Future<void> Function() onRetry;
  final Future<void> Function() onRefresh;
  final List<CommodityQuote> quotes;
  final IconData emptyIcon;
  final bool showVolume;
  final bool showRole;
  final String retryLabel;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return RefreshIndicator(
        onRefresh: onRefresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: const [
            SizedBox(height: 120),
            Center(child: CircularProgressIndicator()),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: quotes.isEmpty
          ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: shellPagePadding(),
              children: [
                const SizedBox(height: 48),
                Icon(emptyIcon, size: 40, color: AppTheme.muted),
                const SizedBox(height: 12),
                Text(
                  emptyMessage,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppTheme.muted),
                ),
                const SizedBox(height: 12),
                Center(
                  child: OutlinedButton(
                    onPressed: onRetry,
                    child: Text(retryLabel),
                  ),
                ),
              ],
            )
          : ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: shellPagePadding(),
              itemCount: quotes.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, i) => IndexQuoteCard(
                quote: quotes[i],
                showVolume: showVolume,
                showRole: showRole,
                onTap: () => openQuoteDetail(context, quotes[i]),
              ),
            ),
    );
  }
}

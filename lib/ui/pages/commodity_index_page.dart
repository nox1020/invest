import 'package:flutter/material.dart';
import 'package:invest/domain/models/commodity_quote.dart';
import 'package:invest/domain/utils/dates.dart';
import 'package:invest/domain/utils/money.dart';
import 'package:invest/state/app_state.dart';
import 'package:invest/ui/layout/page_padding.dart';
import 'package:invest/ui/pages/iran_inflation_pane.dart';
import 'package:invest/ui/pages/quote_detail_page.dart';
import 'package:invest/ui/theme/app_theme.dart';
import 'package:invest/ui/widgets/price_alert_sheet.dart';
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

  List<CommodityQuote> _filteredWallex(List<CommodityQuote> source) {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return source;
    return source
        .where(
          (e) =>
              e.name.toLowerCase().contains(q) ||
              e.symbol.toLowerCase().contains(q) ||
              (e.marketSymbol?.toLowerCase().contains(q) ?? false),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final offlineHint = state.offline ||
        (state.commodityIndexError?.contains('آفلاین') ?? false);
    final wallex = _filteredWallex(state.wallexMarkets);

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
            essentialsCount: state.commodityIndex.length,
            wallexCount: state.wallexMarkets.length,
            inflationPeriod: state.iranInflation?.periodLabel,
            calendar: state.settings.calendar,
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: _SegmentTabs(
            index: _page,
            onChanged: (i) {
              if (i == _page) return;
              setState(() => _page = i);
              if (!_pageController.hasClients) return;
              _pageController.animateToPage(
                i,
                duration: const Duration(milliseconds: 280),
                curve: Curves.easeOutCubic,
              );
            },
          ),
        ),
        if (_page == 1)
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
              _QuoteListPane(
                loading: state.commodityIndexLoading &&
                    state.commodityIndex.isEmpty,
                emptyMessage: state.commodityIndexError ?? 'داده‌ای دریافت نشد',
                onRetry: () =>
                    context.read<AppState>().refreshCommodityIndex(force: true),
                onRefresh: () =>
                    context.read<AppState>().refreshCommodityIndex(force: true),
                quotes: state.commodityIndex,
                emptyIcon: Icons.insights_outlined,
              ),
              _QuoteListPane(
                loading: state.commodityIndexLoading &&
                    state.wallexMarkets.isEmpty,
                emptyMessage: state.wallexMarkets.isEmpty
                    ? (state.commodityIndexError ??
                        'بازار والکس در دسترس نیست')
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
                retryLabel:
                    state.wallexMarkets.isEmpty || _query.isEmpty
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
              label: 'کالاها',
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

class _IndexHeader extends StatelessWidget {
  const _IndexHeader({
    this.updatedAt,
    this.offlineHint = false,
    required this.page,
    required this.essentialsCount,
    required this.wallexCount,
    this.inflationPeriod,
    this.calendar = 'jalali',
  });

  final DateTime? updatedAt;
  final bool offlineHint;
  final int page;
  final int essentialsCount;
  final int wallexCount;
  final String? inflationPeriod;
  final String calendar;

  @override
  Widget build(BuildContext context) {
    final time = updatedAt;
    final title = switch (page) {
      1 => 'بازار والکس',
      2 => 'تورم ایران',
      _ => 'شاخص کالاهای اساسی',
    };
    final subtitle = offlineHint
        ? 'نمایش داده‌های ذخیره‌شده — اتصال اینترنت برای بروزرسانی'
        : switch (page) {
            1 => '$wallexCount بازار تومان — مرتب‌شده بر اساس حجم معامله',
            2 => inflationPeriod == null
                ? 'انواع تورم رسمی مرکز آمار ایران'
                : 'انواع تورم رسمی · $inflationPeriod',
            _ => essentialsCount > 0
                ? '$essentialsCount کالای پرکاربرد — سوایپ کنید برای والکس و تورم'
                : 'کالاهای پرکاربرد — سوایپ کنید برای والکس و تورم',
          };

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: page == 2
              ? const [Color(0xFF3D1A1A), Color(0xFF241212)]
              : const [Color(0xFF1A3D2E), Color(0xFF122820)],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
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
                  _ => Icons.insights_rounded,
                },
                color: page == 2 ? const Color(0xFFFF8A80) : AppTheme.positive,
                size: 22,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            textAlign: TextAlign.right,
            style: TextStyle(
              color: page == 2
                  ? const Color(0xFFD7B0B0)
                  : const Color(0xFFB8D4C6),
              fontSize: 12,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _PageDots(active: page),
              const Spacer(),
              if (time != null)
                Text(
                  'آخرین بروزرسانی: ${_formatUpdatedAt(time, calendar)}',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.7),
                    fontSize: 11,
                  ),
                ),
            ],
          ),
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

class _PageDots extends StatelessWidget {
  const _PageDots({required this.active});

  final int active;

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
                ? AppTheme.positive
                : Colors.white.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(8),
          ),
        );
      }),
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
    this.retryLabel = 'تلاش مجدد',
  });

  final bool loading;
  final String emptyMessage;
  final Future<void> Function() onRetry;
  final Future<void> Function() onRefresh;
  final List<CommodityQuote> quotes;
  final IconData emptyIcon;
  final bool showVolume;
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
              itemBuilder: (context, i) => _CommodityCard(
                quote: quotes[i],
                showVolume: showVolume,
                onTap: () => openQuoteDetail(context, quotes[i]),
              ),
            ),
    );
  }
}

class _CommodityCard extends StatelessWidget {
  const _CommodityCard({
    required this.quote,
    this.showVolume = false,
    this.onTap,
  });

  final CommodityQuote quote;
  final bool showVolume;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final change = quote.change24h;
    Color? changeColor;
    String? changeText;
    if (change != null) {
      changeColor = change > 0
          ? AppTheme.positive
          : (change < 0 ? AppTheme.negative : AppTheme.muted);
      changeText = formatPct(change);
    }

    return Material(
      color: AppTheme.card,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppTheme.border),
          ),
          child: Row(
            children: [
              QuoteAlertBell(quote: quote),
              const Icon(Icons.chevron_left_rounded,
                  color: AppTheme.muted, size: 20),
              if (changeText != null) ...[
                const SizedBox(width: 4),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color:
                        (changeColor ?? AppTheme.muted).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    changeText,
                    style: TextStyle(
                      color: changeColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      quote.name,
                      textAlign: TextAlign.right,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppTheme.title,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                    Text(
                      [
                        quote.symbol,
                        if (showVolume && (quote.quoteVolume24h ?? 0) > 0)
                          'حجم: ${formatCompactToman(quote.quoteVolume24h!)}',
                      ].join('  ·  '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          const TextStyle(color: AppTheme.muted, fontSize: 11),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppTheme.accent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(quote.icon, color: AppTheme.positive, size: 20),
              ),
              const SizedBox(width: 12),
              ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 88, maxWidth: 124),
                child: Text(
                  quote.formatPrice(compact: true),
                  textAlign: TextAlign.left,
                  textDirection: TextDirection.ltr,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppTheme.text,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:invest/domain/models/commodity_quote.dart';
import 'package:invest/domain/utils/money.dart';
import 'package:invest/state/app_state.dart';
import 'package:invest/ui/layout/page_padding.dart';
import 'package:invest/ui/theme/app_theme.dart';
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
        state.refreshCommodityIndex();
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
            updatedAt: state.commodityIndexUpdatedAt,
            offlineHint: offlineHint,
            page: _page,
            essentialsCount: state.commodityIndex.length,
            wallexCount: state.wallexMarkets.length,
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: _SegmentTabs(
            index: _page,
            onChanged: (i) {
              setState(() => _page = i);
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
            onPageChanged: (i) => setState(() => _page = i),
            children: [
              _QuoteListPane(
                loading: state.commodityIndexLoading &&
                    state.commodityIndex.isEmpty,
                emptyMessage: state.commodityIndexError ?? 'داده‌ای دریافت نشد',
                onRetry: state.refreshCommodityIndex,
                onRefresh: state.refreshCommodityIndex,
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
                onRetry: state.refreshCommodityIndex,
                onRefresh: state.refreshCommodityIndex,
                quotes: wallex,
                emptyIcon: Icons.currency_exchange_rounded,
                showVolume: true,
              ),
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
              label: 'کالاهای اساسی',
              selected: index == 0,
              onTap: () => onChanged(0),
            ),
          ),
          Expanded(
            child: _TabChip(
              label: 'بازار والکس',
              selected: index == 1,
              onTap: () => onChanged(1),
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
  });

  final DateTime? updatedAt;
  final bool offlineHint;
  final int page;
  final int essentialsCount;
  final int wallexCount;

  @override
  Widget build(BuildContext context) {
    final time = updatedAt;
    final title = page == 0 ? 'شاخص کالاهای اساسی' : 'بازار والکس';
    final subtitle = offlineHint
        ? 'نمایش قیمت‌های ذخیره‌شده — اتصال اینترنت برای بروزرسانی'
        : (page == 0
            ? '۱۰ کالای پرکاربرد — سوایپ کنید برای همه ارزهای والکس'
            : '$wallexCount بازار تومان — مرتب‌شده بر اساس حجم معامله');

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [Color(0xFF1A3D2E), Color(0xFF122820)],
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
                page == 0
                    ? Icons.insights_rounded
                    : Icons.currency_exchange_rounded,
                color: AppTheme.positive,
                size: 22,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            textAlign: TextAlign.right,
            style: const TextStyle(
              color: Color(0xFFB8D4C6),
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
                  'آخرین بروزرسانی: ${_formatTime(time)}',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.7),
                    fontSize: 11,
                  ),
                ),
            ],
          ),
          if (page == 0 && essentialsCount > 0) ...[
            const SizedBox(height: 4),
            Text(
              '$essentialsCount مورد',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.55),
                fontSize: 11,
              ),
            ),
          ],
        ],
      ),
    );
  }

  static String _formatTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}

class _PageDots extends StatelessWidget {
  const _PageDots({required this.active});

  final int active;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(2, (i) {
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
  });

  final bool loading;
  final String emptyMessage;
  final Future<void> Function() onRetry;
  final Future<void> Function() onRefresh;
  final List<CommodityQuote> quotes;
  final IconData emptyIcon;
  final bool showVolume;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Center(child: CircularProgressIndicator());
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
                    child: const Text('تلاش مجدد'),
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
              ),
            ),
    );
  }
}

class _CommodityCard extends StatelessWidget {
  const _CommodityCard({required this.quote, this.showVolume = false});

  final CommodityQuote quote;
  final bool showVolume;

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

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        children: [
          if (changeText != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: (changeColor ?? AppTheme.muted).withValues(alpha: 0.12),
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
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  quote.name,
                  textAlign: TextAlign.right,
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
                      'حجم: ${formatNumber(quote.quoteVolume24h!, decimals: 0)}',
                  ].join('  ·  '),
                  style: const TextStyle(color: AppTheme.muted, fontSize: 11),
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
          SizedBox(
            width: 120,
            child: Text(
              _formatPrice(quote),
              textAlign: TextAlign.left,
              textDirection: TextDirection.ltr,
              style: const TextStyle(
                color: AppTheme.text,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _formatPrice(CommodityQuote q) {
    final p = q.price;
    if (p == null) return '—';
    switch (q.unit) {
      case 'usd':
        return '\$${formatNumber(p, decimals: p >= 1000 ? 0 : 2)}';
      case 'toman_per_gram':
        return '${formatNumber(p, decimals: 0)} ت/گرم';
      case 'toman':
      default:
        final decimals = p >= 1000 ? 0 : (p >= 1 ? 2 : 4);
        return '${formatNumber(p, decimals: decimals)} تومان';
    }
  }
}

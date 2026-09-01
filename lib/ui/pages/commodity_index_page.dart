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
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final state = context.read<AppState>();
      if (state.commodityIndex.isEmpty && !state.commodityIndexLoading) {
        state.refreshCommodityIndex();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    return RefreshIndicator(
      onRefresh: state.refreshCommodityIndex,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: shellPagePadding(),
        children: [
          _IndexHeader(updatedAt: state.commodityIndexUpdatedAt),
          const SizedBox(height: 12),
          if (state.commodityIndexLoading && state.commodityIndex.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 48),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (state.commodityIndex.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Column(
                children: [
                  Text(
                    state.commodityIndexError ?? 'داده‌ای دریافت نشد',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppTheme.muted),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: state.refreshCommodityIndex,
                    child: const Text('تلاش مجدد'),
                  ),
                ],
              ),
            )
          else
            ...state.commodityIndex.map(
              (q) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _CommodityCard(quote: q),
              ),
            ),
        ],
      ),
    );
  }
}

class _IndexHeader extends StatelessWidget {
  const _IndexHeader({this.updatedAt});

  final DateTime? updatedAt;

  @override
  Widget build(BuildContext context) {
    final time = updatedAt;
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
          const Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Text(
                'شاخص کالاهای اساسی',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(width: 8),
              Icon(Icons.insights_rounded, color: AppTheme.positive, size: 22),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'نرخ ۱۰ کالای پرکاربرد — ارز، طلا، سکه و رمزارز',
            textAlign: TextAlign.right,
            style: TextStyle(color: Color(0xFFB8D4C6), fontSize: 12, height: 1.4),
          ),
          if (time != null) ...[
            const SizedBox(height: 8),
            Text(
              'آخرین بروزرسانی: ${_formatTime(time)}',
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

  static String _formatTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}

class _CommodityCard extends StatelessWidget {
  const _CommodityCard({required this.quote});

  final CommodityQuote quote;

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
                  quote.symbol,
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
        return '${formatNumber(p, decimals: 0)} تومان';
    }
  }
}

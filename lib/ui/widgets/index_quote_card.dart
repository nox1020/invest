import 'package:flutter/material.dart';
import 'package:invest/domain/models/commodity_quote.dart';
import 'package:invest/domain/services/index_analytics.dart';
import 'package:invest/domain/utils/money.dart';
import 'package:invest/ui/theme/app_theme.dart';
import 'package:invest/ui/widgets/price_alert_sheet.dart';

class IndexQuoteCard extends StatelessWidget {
  const IndexQuoteCard({
    super.key,
    required this.quote,
    this.showVolume = false,
    this.showRole = true,
    this.showAlert = true,
    this.onTap,
  });

  final CommodityQuote quote;
  final bool showVolume;
  final bool showRole;
  final bool showAlert;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final change = quote.change24h;
    final tone = change == null
        ? AppTheme.muted
        : (change > 0
            ? AppTheme.positive
            : (change < 0 ? AppTheme.negative : AppTheme.muted));
    final position = rangePosition(quote);
    final spread = spreadLabel(quote);
    final volume = showVolume && (quote.quoteVolume24h ?? 0) > 0
        ? 'حجم ${formatCompactToman(quote.quoteVolume24h!)}'
        : null;
    final meta = [
      if (volume != null) volume,
      if (spread != null) spread,
      if (position != null) rangeCaption(position)!,
    ].join(' · ');

    return Material(
      color: AppTheme.card,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.border),
          ),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(width: 4, color: tone),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: tone.withValues(alpha: 0.14),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(quote.icon, color: tone, size: 20),
                            ),
                            const SizedBox(width: 10),
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
                                      fontWeight: FontWeight.w800,
                                      fontSize: 15,
                                    ),
                                  ),
                                  if (showRole) ...[
                                    const SizedBox(height: 2),
                                    Text(
                                      indexRoleLabel(quote),
                                      textAlign: TextAlign.right,
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
                            const SizedBox(width: 10),
                            Flexible(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    quote.formatPrice(compact: true),
                                    textDirection: TextDirection.ltr,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: AppTheme.title,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 15,
                                    ),
                                  ),
                                  if (change != null) ...[
                                    const SizedBox(height: 4),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 3,
                                      ),
                                      decoration: BoxDecoration(
                                        color: tone.withValues(alpha: 0.14),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        formatPct(change),
                                        style: TextStyle(
                                          color: tone,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            if (showAlert) ...[
                              const SizedBox(width: 4),
                              QuoteAlertBell(quote: quote),
                            ],
                          ],
                        ),
                        if (position != null) ...[
                          const SizedBox(height: 10),
                          QuoteRangeBar(position: position, color: tone),
                        ],
                        if (meta.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(
                            meta,
                            textAlign: TextAlign.right,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppTheme.muted,
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class QuoteRangeBar extends StatelessWidget {
  const QuoteRangeBar({
    super.key,
    required this.position,
    this.color = AppTheme.positive,
  });

  final double position;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final t = position.clamp(0.0, 1.0);
    return SizedBox(
      height: 8,
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final marker = (constraints.maxWidth - 8) * t;
            return Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  height: 3,
                  decoration: BoxDecoration(
                    color: AppTheme.border,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
                Positioned(
                  left: marker,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppTheme.card, width: 1.5),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:invest/ui/theme/app_theme.dart';

class MetricCard extends StatelessWidget {
  const MetricCard({
    super.key,
    required this.title,
    required this.value,
    this.caption,
    this.tone,
    this.hero = false,
  });

  final String title;
  final String value;
  final String? caption;
  final String? tone; // positive | negative
  final bool hero;

  @override
  Widget build(BuildContext context) {
    Color valueColor = AppTheme.title;
    if (tone == 'positive') valueColor = AppTheme.positive;
    if (tone == 'negative') valueColor = AppTheme.negative;

    return Container(
      padding: EdgeInsets.all(hero ? 20 : 14),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(hero ? 18 : 12),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            textAlign: TextAlign.right,
            style: TextStyle(
              color: AppTheme.muted,
              fontSize: hero ? 12 : 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          SizedBox(height: hero ? 12 : 8),
          Text(
            value,
            textAlign: TextAlign.right,
            style: TextStyle(
              color: valueColor,
              fontSize: hero ? 24 : 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          if (caption != null && caption!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              caption!,
              textAlign: TextAlign.right,
              style: const TextStyle(color: AppTheme.muted, fontSize: 11),
            ),
          ],
        ],
      ),
    );
  }
}

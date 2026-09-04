import 'package:flutter/material.dart';
import 'package:invest/ui/theme/app_theme.dart';

class OfflineReadOnlyNotice extends StatelessWidget {
  const OfflineReadOnlyNotice({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
      ),
      child: const Text(
        'در حالت آفلاین فقط مشاهده فعال است. برای ثبت معامله آنلاین شوید.',
        textAlign: TextAlign.right,
        style: TextStyle(color: AppTheme.muted, fontSize: 12, height: 1.4),
      ),
    );
  }
}

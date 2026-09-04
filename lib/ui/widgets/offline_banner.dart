import 'package:flutter/material.dart';
import 'package:invest/ui/theme/app_theme.dart';

/// Compact status strip shown while the app runs without network.
class OfflineBanner extends StatelessWidget {
  const OfflineBanner({
    super.key,
    required this.message,
    this.onReconnect,
    this.reconnecting = false,
  });

  final String message;
  final VoidCallback? onReconnect;
  final bool reconnecting;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF2A2112),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              if (onReconnect != null)
                TextButton(
                  onPressed: reconnecting ? null : onReconnect,
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFFE8C878),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(reconnecting ? '…' : 'اتصال'),
                ),
              Expanded(
                child: Text(
                  message,
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    color: Color(0xFFE8C878),
                    fontSize: 12,
                    height: 1.35,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.wifi_off_rounded,
                size: 18,
                color: const Color(0xFFE8C878).withValues(alpha: 0.9),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

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

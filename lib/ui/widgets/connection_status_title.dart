import 'package:flutter/material.dart';
import 'package:invest/domain/services/connection_status.dart';
import 'package:invest/ui/widgets/dashboard_kit.dart' show fa;

export 'package:invest/domain/services/connection_status.dart';

/// Two-line AppBar title: page name + Telegram-like connection subtitle.
class ConnectionStatusTitle extends StatelessWidget {
  const ConnectionStatusTitle({
    super.key,
    required this.pageTitle,
    required this.status,
    this.pending = 0,
  });

  final String pageTitle;
  final AppConnectionStatus status;

  /// Unsent queued writes; shown after the status («· ۲ در صف»).
  final int pending;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          pageTitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 17,
            fontWeight: FontWeight.w600,
            height: 1.15,
          ),
        ),
        const SizedBox(height: 2),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          switchInCurve: Curves.easeOut,
          switchOutCurve: Curves.easeIn,
          child: Row(
            key: ValueKey('$status-$pending'),
            children: [
              _StatusDot(status: status),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  pending > 0
                      ? '${status.label} — ${fa('$pending')} تغییر در صف'
                      : status.label,
                  key: const ValueKey('conn-status'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: status.color,
                    fontSize: 12,
                    height: 1.1,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.status});

  final AppConnectionStatus status;

  @override
  Widget build(BuildContext context) {
    if (status == AppConnectionStatus.updating ||
        status == AppConnectionStatus.connecting) {
      return SizedBox(
        width: 8,
        height: 8,
        child: CircularProgressIndicator(
          strokeWidth: 1.4,
          color: status.color,
        ),
      );
    }
    return Container(
      width: 7,
      height: 7,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: status.color,
      ),
    );
  }
}

/// Thin indeterminate bar along the AppBar bottom — Telegram updating cue.
class ConnectionProgressBar extends StatelessWidget {
  const ConnectionProgressBar({super.key});

  @override
  Widget build(BuildContext context) {
    return const LinearProgressIndicator(
      minHeight: 2,
      backgroundColor: Color(0x22FFFFFF),
      color: Colors.white,
    );
  }
}

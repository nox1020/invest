import 'package:flutter/material.dart';

/// Telegram-style connection state shown under the page title.
enum AppConnectionStatus {
  connected,
  updating,
  offline;

  String get label => switch (this) {
        connected => 'متصل',
        updating => 'در حال به‌روزرسانی...',
        offline => 'آفلاین',
      };

  Color get color => switch (this) {
        connected => const Color(0xFF6EE7A8),
        updating => const Color(0xFFE8F0EC),
        offline => const Color(0xFFB7C4BC),
      };

  static AppConnectionStatus resolve({
    required bool offline,
    required bool updating,
  }) {
    if (updating) return AppConnectionStatus.updating;
    if (offline) return AppConnectionStatus.offline;
    return AppConnectionStatus.connected;
  }
}

/// Two-line AppBar title: page name + Telegram-like connection subtitle.
class ConnectionStatusTitle extends StatelessWidget {
  const ConnectionStatusTitle({
    super.key,
    required this.pageTitle,
    required this.status,
  });

  final String pageTitle;
  final AppConnectionStatus status;

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
            key: ValueKey(status),
            children: [
              _StatusDot(status: status),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  status.label,
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
    if (status == AppConnectionStatus.updating) {
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

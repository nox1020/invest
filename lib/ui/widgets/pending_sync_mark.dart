import 'package:flutter/material.dart';

/// Small «در صف» tag on a row that is saved on this phone but not yet on
/// the server (offline edit waiting in the outbox / store queue).
class PendingSyncMark extends StatelessWidget {
  const PendingSyncMark({super.key, required this.pending, required this.child});
  final bool pending;
  final Widget child;

  static const amber = Color(0xFFE0C46A);

  @override
  Widget build(BuildContext context) {
    if (!pending) return child;
    return Stack(clipBehavior: Clip.none, children: [
      child,
      PositionedDirectional(
        top: -9,
        start: 14,
        child: IgnorePointer(
          child: Container(
            key: const ValueKey('pending-sync-mark'),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: amber.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: amber.withValues(alpha: 0.7)),
            ),
            child: const Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.cloud_upload_outlined, size: 11, color: amber),
              SizedBox(width: 3),
              Text('در صف', style: TextStyle(color: amber, fontSize: 10, height: 1.2)),
            ]),
          ),
        ),
      ),
    ]);
  }
}

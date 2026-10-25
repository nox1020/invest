import 'package:flutter/material.dart';

/// Bottom-nav indices for [HomeShell].
abstract final class HomeTabs {
  static const dashboard = 0;
  static const withdrawals = 1;
  static const trades = 2;
  /// «عملکرد» (office monthly table). The old «شاخص» tab lives on the
  /// dashboard now.
  static const performance = 3;
  static const settings = 4;
}

/// Bubbles a tab change up to [HomeShell] without importing it.
class OpenHomeTabNotification extends Notification {
  const OpenHomeTabNotification(this.index);
  final int index;
}

/// Set by the home shell so pushed routes (outside its subtree) can switch
/// tabs too.
void Function(int index)? homeTabSwitcher;

/// Switches the bottom tab. From a pushed page pass [popToRoot] so the
/// shell becomes visible.
void openHomeTab(BuildContext context, int index, {bool popToRoot = false}) {
  if (popToRoot) {
    Navigator.of(context).popUntil((r) => r.isFirst);
  }
  final go = homeTabSwitcher;
  if (go != null) {
    go(index);
  } else {
    OpenHomeTabNotification(index).dispatch(context);
  }
}

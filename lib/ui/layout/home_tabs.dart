import 'package:flutter/material.dart';

/// Bottom-nav indices for [HomeShell].
abstract final class HomeTabs {
  static const dashboard = 0;
  static const withdrawals = 1;
  static const trades = 2;
  static const index = 3;
  static const settings = 4;
}

/// Bubbles a tab change up to [HomeShell] without importing it.
class OpenHomeTabNotification extends Notification {
  const OpenHomeTabNotification(this.index);
  final int index;
}

void openHomeTab(BuildContext context, int index) {
  OpenHomeTabNotification(index).dispatch(context);
}

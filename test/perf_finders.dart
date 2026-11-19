import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Finds a keyed widget even when it is below the fold in a ListView.
Finder keyOnOrOff(Key key) => find.byKey(key, skipOffstage: false);

/// Scrolls [key] into view. The widget must already be in the tree.
Future<void> revealKey(WidgetTester tester, Key key) async {
  final finder = keyOnOrOff(key);
  expect(finder, findsWidgets);
  await tester.ensureVisible(finder.first);
  await tester.pumpAndSettle();
}

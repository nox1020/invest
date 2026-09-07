import 'package:flutter/material.dart';
import 'package:invest/ui/pages/assets_page.dart';

/// Assets list under the bottom-nav «معاملات» tab.
/// Open/closed trades live on each asset's detail page.
class TradesHubPage extends StatelessWidget {
  const TradesHubPage({super.key});

  @override
  Widget build(BuildContext context) => const AssetsPage();
}

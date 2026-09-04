import 'package:flutter/material.dart';
import 'package:invest/ui/pages/assets_page.dart';
import 'package:invest/ui/pages/trades_page.dart';
import 'package:invest/ui/theme/app_theme.dart';

/// Assets + open/closed trades in one bottom-nav tab.
class TradesHubPage extends StatefulWidget {
  const TradesHubPage({super.key, this.onSegmentChanged});

  final ValueChanged<int>? onSegmentChanged;

  @override
  State<TradesHubPage> createState() => _TradesHubPageState();
}

class _TradesHubPageState extends State<TradesHubPage> {
  int _segment = 0;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: SegmentedButton<int>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: 0, label: Text('دارایی')),
              ButtonSegment(value: 1, label: Text('باز')),
              ButtonSegment(value: 2, label: Text('بسته')),
            ],
            selected: {_segment},
            onSelectionChanged: (value) {
              setState(() => _segment = value.first);
              widget.onSegmentChanged?.call(_segment);
            },
            style: ButtonStyle(
              visualDensity: VisualDensity.compact,
              backgroundColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.selected)) {
                  return AppTheme.accent;
                }
                return AppTheme.card;
              }),
              foregroundColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.selected)) {
                  return Colors.white;
                }
                return AppTheme.muted;
              }),
            ),
          ),
        ),
        Expanded(
          child: IndexedStack(
            index: _segment,
            children: const [
              AssetsPage(),
              TradesPage(open: true),
              TradesPage(open: false),
            ],
          ),
        ),
      ],
    );
  }
}

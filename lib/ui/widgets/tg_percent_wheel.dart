import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:invest/config/app_config.dart';
import 'package:invest/domain/models/app_settings.dart';
import 'package:invest/ui/theme/app_theme.dart';
import 'package:invest/ui/widgets/settings_ui.dart';

/// Telegram-style rotary percent picker (1–100) with selection haptics.
Future<int?> showTgPercentWheel({
  required BuildContext context,
  required String title,
  required int selected,
  String subtitle = 'چرخ را بچرخانید · ۱ تا ۱۰۰ درصد از ورودی',
  int min = AppConfig.minAnnualWithdrawalPct,
  int max = AppConfig.maxAnnualWithdrawalPct,
}) {
  final initial = selected.clamp(min, max);
  return showModalBottomSheet<int>(
    context: context,
    backgroundColor: tgSettingsGroupBg(context),
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
    ),
    builder: (ctx) => _TgPercentWheelSheet(
      title: title,
      subtitle: subtitle,
      initial: initial,
      min: min,
      max: max,
    ),
  );
}

class _TgPercentWheelSheet extends StatefulWidget {
  const _TgPercentWheelSheet({
    required this.title,
    required this.subtitle,
    required this.initial,
    required this.min,
    required this.max,
  });

  final String title;
  final String subtitle;
  final int initial;
  final int min;
  final int max;

  @override
  State<_TgPercentWheelSheet> createState() => _TgPercentWheelSheetState();
}

class _TgPercentWheelSheetState extends State<_TgPercentWheelSheet> {
  static const _itemExtent = 40.0;
  late final FixedExtentScrollController _controller;
  late int _value;
  int? _lastHaptic;

  @override
  void initState() {
    super.initState();
    _value = widget.initial;
    _lastHaptic = _value;
    _controller = FixedExtentScrollController(
      initialItem: _value - widget.min,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onSelected(int index) {
    final next = widget.min + index;
    if (next == _value) return;
    setState(() => _value = next);
    if (_lastHaptic != next) {
      _lastHaptic = next;
      HapticFeedback.selectionClick();
    }
  }

  @override
  Widget build(BuildContext context) {
    final count = widget.max - widget.min + 1;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppTheme.muted.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              widget.title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: AppTheme.title,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              widget.subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: AppTheme.muted),
            ),
            const SizedBox(height: 8),
            Text(
              AppSettings.annualWithdrawalShortLabel(_value),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w800,
                color: AppTheme.positive,
                height: 1.1,
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: _itemExtent * 5,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Telegram-like selection band.
                  IgnorePointer(
                    child: Container(
                      height: _itemExtent,
                      margin: const EdgeInsets.symmetric(horizontal: 8),
                      decoration: BoxDecoration(
                        color: AppTheme.accent.withValues(alpha: 0.22),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: AppTheme.accent.withValues(alpha: 0.45),
                        ),
                      ),
                    ),
                  ),
                  ListWheelScrollView.useDelegate(
                    controller: _controller,
                    itemExtent: _itemExtent,
                    physics: const FixedExtentScrollPhysics(),
                    perspective: 0.003,
                    diameterRatio: 1.15,
                    squeeze: 1,
                    onSelectedItemChanged: _onSelected,
                    childDelegate: ListWheelChildBuilderDelegate(
                      childCount: count,
                      builder: (context, index) {
                        final pct = widget.min + index;
                        final selected = pct == _value;
                        return Center(
                          child: Text(
                            AppSettings.annualWithdrawalShortLabel(pct),
                            style: TextStyle(
                              fontSize: selected ? 22 : 17,
                              fontWeight:
                                  selected ? FontWeight.w800 : FontWeight.w500,
                              color: selected
                                  ? AppTheme.title
                                  : AppTheme.muted.withValues(alpha: 0.75),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  // Soft fade at top/bottom like Telegram.
                  IgnorePointer(
                    child: Column(
                      children: [
                        Container(
                          height: _itemExtent * 1.4,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                tgSettingsGroupBg(context),
                                tgSettingsGroupBg(context).withValues(alpha: 0),
                              ],
                            ),
                          ),
                        ),
                        const Spacer(),
                        Container(
                          height: _itemExtent * 1.4,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.bottomCenter,
                              end: Alignment.topCenter,
                              colors: [
                                tgSettingsGroupBg(context),
                                tgSettingsGroupBg(context).withValues(alpha: 0),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('انصراف'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      // Prefer the controller's settled item — `_value` can lag
                      // while the wheel is still flinging.
                      final index = _controller.hasClients
                          ? _controller.selectedItem
                          : (_value - widget.min);
                      final pct = (widget.min + index).clamp(
                        widget.min,
                        widget.max,
                      );
                      Navigator.pop(context, pct);
                    },
                    child: const Text('تأیید'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

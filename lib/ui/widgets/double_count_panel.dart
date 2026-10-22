import 'package:flutter/material.dart';
import 'package:invest/data/local_platform.dart';
import 'package:invest/domain/models/withdrawal.dart';
import 'package:invest/domain/services/double_count.dart';
import 'package:invest/domain/services/pwo_ledger.dart';
import 'package:invest/domain/utils/money.dart';
import 'package:invest/ui/theme/app_theme.dart';

const _monthsFa = [
  'فروردین', 'اردیبهشت', 'خرداد', 'تیر', 'مرداد', 'شهریور',
  'مهر', 'آبان', 'آذر', 'دی', 'بهمن', 'اسفند',
];

/// Warns when a withdrawal looks recorded both in the withdrawal ledger and
/// in PWO. Never deletes or edits anything; "تکراری نیست" only hides it.
class DoubleCountPanel extends StatefulWidget {
  const DoubleCountPanel({super.key, required this.withdrawals, required this.ledger});
  final List<Withdrawal> withdrawals;
  final PwoLedger ledger;

  static const prefKey = 'vplus_double_count_ok_v1';

  @override
  State<DoubleCountPanel> createState() => _DoubleCountPanelState();
}

class _DoubleCountPanelState extends State<DoubleCountPanel> {
  Set<String> _ok = {};

  @override
  void initState() {
    super.initState();
    LocalPrefs.open().then((p) {
      final l = p?.getStringList(DoubleCountPanel.prefKey);
      if (l != null && mounted) setState(() => _ok = l.toSet());
    });
  }

  Future<void> _save() async {
    final p = await LocalPrefs.open();
    await p?.setStringList(DoubleCountPanel.prefKey, _ok.toList());
  }

  @override
  Widget build(BuildContext context) {
    final all = findDoubleCounts(widget.withdrawals, widget.ledger);
    final hits = [for (final h in all) if (!_ok.contains(h.key)) h];
    final hidden = all.length - hits.length;
    if (hits.isEmpty && hidden == 0) return const SizedBox.shrink();
    if (hits.isEmpty) {
      return Align(
        alignment: Alignment.centerRight,
        child: TextButton(
          key: const ValueKey('dc-unhide'),
          onPressed: () {
            setState(() => _ok.removeAll(all.map((h) => h.key)));
            _save();
          },
          child: Text('نمایش دوبارهٔ $hidden مورد احتمال ثبت دوباره'),
        ),
      );
    }
    return Container(
      key: const ValueKey('dc-panel'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFE0C46A).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE0C46A).withValues(alpha: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Row(children: [
            Spacer(),
            Flexible(
              flex: 8,
              child: Text('احتمال ثبت دوباره در دفتر برداشت و PWO',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                      color: AppTheme.title, fontWeight: FontWeight.w800, fontSize: 13)),
            ),
            SizedBox(width: 6),
            Icon(Icons.warning_amber_rounded, color: Color(0xFFE0C46A), size: 20),
          ]),
          const SizedBox(height: 6),
          const Text(doubleCountDefinitions,
              key: ValueKey('dc-defs'),
              textAlign: TextAlign.right,
              style: TextStyle(color: AppTheme.muted, fontSize: 11, height: 1.5)),
          for (final h in hits)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(children: [
                TextButton(
                  key: ValueKey('dc-ok-${h.key}'),
                  onPressed: () {
                    setState(() => _ok.add(h.key));
                    _save();
                  },
                  child: const Text('تکراری نیست'),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'برداشت ${formatMoney(h.withdrawal.amount)} در ${_monthsFa[h.month - 1]} ${h.year}'
                    ' = ${h.match} در PWO (${formatMoney(h.pwoAmount)})',
                    key: ValueKey('dc-hit-${h.key}'),
                    textAlign: TextAlign.right,
                    style: const TextStyle(color: AppTheme.title, fontSize: 12),
                  ),
                ),
              ]),
            ),
          const SizedBox(height: 6),
          const Text(
              'اگر واقعاً تکراری است، خودتان یکی را ویرایش یا حذف کنید؛ اپ چیزی را خودکار پاک نمی‌کند.',
              textAlign: TextAlign.right,
              style: TextStyle(color: AppTheme.muted, fontSize: 11)),
        ],
      ),
    );
  }
}

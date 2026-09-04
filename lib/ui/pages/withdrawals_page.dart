import 'package:flutter/material.dart';
import 'package:invest/domain/models/withdrawal.dart';
import 'package:invest/domain/utils/dates.dart';
import 'package:invest/domain/utils/money.dart';
import 'package:invest/state/app_state.dart';
import 'package:invest/ui/layout/page_padding.dart';
import 'package:invest/ui/theme/app_theme.dart';
import 'package:invest/ui/widgets/metric_card.dart';
import 'package:provider/provider.dart';

class WithdrawalsPage extends StatelessWidget {
  const WithdrawalsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final history = state.withdrawals;

    return RefreshIndicator(
      onRefresh: () => state.refreshAll(),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: shellPagePadding(extraForFab: state.canMutate),
        children: [
          MetricCard(
            title: 'مبلغ قابل برداشت',
            value: formatMoney(state.withdrawableAmount),
            caption: state.withdrawnTotal > 0
                ? 'مجموع برداشت‌شده: ${formatMoney(state.withdrawnTotal)}'
                : 'از سود تحقق‌یافته منهای برداشت‌های ثبت‌شده',
            hero: true,
            tone: state.withdrawableAmount > 0 ? 'positive' : null,
          ),
          const SizedBox(height: 22),
          const Text(
            'سابقه برداشت',
            textAlign: TextAlign.right,
            style: TextStyle(
              color: AppTheme.title,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 10),
          if (history.isEmpty)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 16),
              decoration: BoxDecoration(
                color: AppTheme.card,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.border),
              ),
              child: const Text(
                'هنوز برداشتی ثبت نشده',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppTheme.muted),
              ),
            )
          else
            for (var i = 0; i < history.length; i++) ...[
              if (i > 0) const SizedBox(height: 8),
              _WithdrawalTile(item: history[i]),
            ],
        ],
      ),
    );
  }
}

Future<void> showRecordWithdrawalDialog(BuildContext context) async {
  final state = context.read<AppState>();
  final available = state.withdrawableAmount;
  if (available <= 0) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('مبلغ قابل برداشت صفر است')),
    );
    return;
  }
  final amountCtrl = TextEditingController();
  final noteCtrl = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('ثبت برداشت'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'قابل برداشت: ${formatMoney(available)}',
              textAlign: TextAlign.right,
              style: const TextStyle(color: AppTheme.muted, fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: amountCtrl,
              decoration: const InputDecoration(labelText: 'مبلغ (تومان)'),
              keyboardType: TextInputType.number,
              textAlign: TextAlign.right,
            ),
            TextField(
              controller: noteCtrl,
              decoration: const InputDecoration(labelText: 'توضیح (اختیاری)'),
              textAlign: TextAlign.right,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('انصراف'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('ثبت'),
        ),
      ],
    ),
  );
  if (ok != true || !context.mounted) return;
  try {
    await state.recordWithdrawal(
      amount: double.parse(amountCtrl.text.replaceAll(',', '').trim()),
      note: noteCtrl.text.trim(),
    );
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('برداشت ثبت شد')),
      );
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }
}

class _WithdrawalTile extends StatelessWidget {
  const _WithdrawalTile({required this.item});
  final Withdrawal item;

  @override
  Widget build(BuildContext context) {
    final calendar = context.read<AppState>().settings.calendar;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            formatMoney(item.amount),
            textAlign: TextAlign.right,
            style: const TextStyle(
              color: AppTheme.title,
              fontWeight: FontWeight.w800,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            [
              item.statusLabel,
              formatDisplayDate(item.createdAt, calendar),
            ].join('  ·  '),
            textAlign: TextAlign.right,
            style: const TextStyle(color: AppTheme.muted, fontSize: 12),
          ),
          if (item.note.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              item.note,
              textAlign: TextAlign.right,
              style: const TextStyle(color: AppTheme.muted, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }
}

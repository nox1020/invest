import 'package:flutter/material.dart';
import 'package:invest/domain/models/app_settings.dart';
import 'package:invest/domain/models/withdrawal.dart';
import 'package:invest/domain/services/withdrawal_allowance.dart';
import 'package:invest/domain/utils/dates.dart';
import 'package:invest/domain/utils/money.dart';
import 'package:invest/state/app_state.dart';
import 'package:invest/ui/layout/home_tabs.dart';
import 'package:invest/ui/layout/page_padding.dart';
import 'package:invest/ui/theme/app_theme.dart';
import 'package:invest/ui/widgets/app_date_picker.dart';
import 'package:invest/ui/widgets/user_error.dart';
import 'package:provider/provider.dart';

class WithdrawalsPage extends StatelessWidget {
  const WithdrawalsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final history = state.withdrawals;
    final allowance = state.withdrawalAllowance;

    return RefreshIndicator(
      onRefresh: () => state.refreshAll(),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: shellPagePadding(extraForFab: state.canMutate),
        children: [
          _AllowanceHero(allowance: allowance),
          const SizedBox(height: 12),
          _AllowanceBreakdown(allowance: allowance),
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
                borderRadius: BorderRadius.circular(16),
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
              _WithdrawalTile(
                item: history[i],
                canEdit: state.canMutate,
              ),
            ],
        ],
      ),
    );
  }
}

class _AllowanceHero extends StatelessWidget {
  const _AllowanceHero({required this.allowance});
  final WithdrawalAllowance allowance;

  @override
  Widget build(BuildContext context) {
    final available = allowance.available;
    final yearLabel =
        WithdrawalAllowance.yearCaption(allowance.yearKey, allowance.calendar);
    final pctLabel = AppSettings.annualWithdrawalLabel(allowance.annualPct);
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'مبلغ قابل برداشت',
            textAlign: TextAlign.right,
            style: TextStyle(
              color: AppTheme.muted,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            formatMoney(available),
            textAlign: TextAlign.right,
            style: TextStyle(
              color: available > 0 ? AppTheme.positive : AppTheme.title,
              fontSize: 26,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'سقف $pctLabel در $yearLabel',
            textAlign: TextAlign.right,
            style: const TextStyle(color: AppTheme.muted, fontSize: 12),
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: allowance.usedAnnualFraction,
              minHeight: 7,
              backgroundColor: AppTheme.border,
              color: allowance.remainingAnnual <= 1e-6
                  ? AppTheme.negative
                  : AppTheme.positive,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            allowance.annualCap <= 0
                ? 'سقف سالانه صفر است؛ ورودی پرتفو ثبت نشده'
                : 'برداشت امسال ${formatMoney(allowance.yearWithdrawn)} از ${formatMoney(allowance.annualCap)}',
            textAlign: TextAlign.right,
            style: const TextStyle(color: AppTheme.muted, fontSize: 11),
          ),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => openHomeTab(context, HomeTabs.settings),
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 4),
              ),
              child: const Text('تغییر درصد در تنظیمات'),
            ),
          ),
        ],
      ),
    );
  }
}

class _AllowanceBreakdown extends StatelessWidget {
  const _AllowanceBreakdown({required this.allowance});
  final WithdrawalAllowance allowance;

  @override
  Widget build(BuildContext context) {
    final pct = AppSettings.annualWithdrawalShortLabel(allowance.annualPct);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 6),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        children: [
          _BreakdownRow(label: 'کل ورودی پرتفو', value: allowance.inflows),
          _BreakdownRow(label: 'سقف سالانه ($pct)', value: allowance.annualCap),
          _BreakdownRow(label: 'برداشت امسال', value: allowance.yearWithdrawn),
          _BreakdownRow(
            label: 'باقیمانده سقف سالانه',
            value: allowance.remainingAnnual,
          ),
          _BreakdownRow(
            label: 'سود تحقق‌یافته باقیمانده',
            value: allowance.remainingRealized,
            showDivider: false,
          ),
        ],
      ),
    );
  }
}

class _BreakdownRow extends StatelessWidget {
  const _BreakdownRow({
    required this.label,
    required this.value,
    this.showDivider = true,
  });

  final String label;
  final double value;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            children: [
              Text(
                label,
                textAlign: TextAlign.right,
                style: const TextStyle(
                  color: AppTheme.muted,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  formatMoney(value),
                  textAlign: TextAlign.left,
                  style: const TextStyle(
                    color: AppTheme.title,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (showDivider)
          const Divider(height: 1, color: AppTheme.border),
      ],
    );
  }
}

Future<void> showRecordWithdrawalDialog(
  BuildContext context, {
  Withdrawal? existing,
}) async {
  final state = context.read<AppState>();
  if (!state.canMutate) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('در حالت آفلاین فقط مشاهده ممکن است. برای ذخیره آنلاین شوید.'),
      ),
    );
    return;
  }
  final draft = existing;
  if (draft != null && draft.id == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('این برداشت قابل ویرایش نیست.')),
    );
    return;
  }
  final editing = draft != null;
  final allowance = state.withdrawalAllowance;
  final available = allowance.available;
  final amountCtrl = TextEditingController(
    text: draft == null ? '' : _amountFieldText(draft.amount),
  );
  final noteCtrl = TextEditingController(text: draft?.note ?? '');
  var createdAt = todayIso();
  if (draft != null && draft.createdAt.trim().isNotEmpty) {
    createdAt = tryNormalizeToIso(draft.createdAt) ?? todayIso();
  }
  final pctLabel = AppSettings.annualWithdrawalLabel(allowance.annualPct);
  final calendar = state.settings.calendar;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) => AlertDialog(
        title: Text(editing ? 'ویرایش برداشت' : 'ثبت برداشت'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'قابل برداشت: ${formatMoney(available)}',
                textAlign: TextAlign.right,
                style: TextStyle(
                  color: available > 0 ? AppTheme.positive : AppTheme.muted,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'سقف امسال $pctLabel · باقیمانده سقف ${formatMoney(allowance.remainingAnnual)}',
                textAlign: TextAlign.right,
                style: const TextStyle(color: AppTheme.muted, fontSize: 12),
              ),
              const SizedBox(height: 6),
              const Text(
                'مبلغ می‌تواند بیشتر از قابل برداشت باشد.',
                textAlign: TextAlign.right,
                style: TextStyle(color: AppTheme.muted, fontSize: 12),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: amountCtrl,
                decoration: const InputDecoration(labelText: 'مبلغ (تومان)'),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                textAlign: TextAlign.right,
              ),
              TextField(
                controller: noteCtrl,
                decoration: const InputDecoration(labelText: 'توضیح (اختیاری)'),
                textAlign: TextAlign.right,
              ),
              if (editing)
                AppDateTile(
                  label: 'تاریخ برداشت',
                  isoDate: createdAt,
                  calendar: calendar,
                  onChanged: (v) => setLocal(() => createdAt = v),
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
            child: Text(editing ? 'ذخیره' : 'ثبت'),
          ),
        ],
      ),
    ),
  );
  if (ok != true || !context.mounted) {
    amountCtrl.dispose();
    noteCtrl.dispose();
    return;
  }
  final parsed = parseFlexibleNumber(amountCtrl.text);
  final note = noteCtrl.text.trim();
  amountCtrl.dispose();
  noteCtrl.dispose();
  if (parsed == null || parsed <= 0) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('مبلغ برداشت نامعتبر است')),
    );
    return;
  }
  try {
    if (draft != null) {
      await state.updateWithdrawal(
        item: draft,
        amount: parsed,
        note: note,
        createdAt: createdAt,
      );
    } else {
      await state.recordWithdrawal(
        amount: parsed,
        note: note,
      );
    }
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(editing ? 'برداشت ویرایش شد' : 'برداشت ثبت شد'),
        ),
      );
    }
  } catch (e) {
    if (context.mounted) showUserError(context, e);
  }
}

String _amountFieldText(double amount) {
  if ((amount - amount.roundToDouble()).abs() < 1e-9) {
    return amount.round().toString();
  }
  var text = amount.toStringAsFixed(4);
  text = text.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
  return text;
}

class _WithdrawalTile extends StatelessWidget {
  const _WithdrawalTile({required this.item, required this.canEdit});
  final Withdrawal item;
  final bool canEdit;

  Color get _statusColor => switch (item.status) {
        'rejected' => AppTheme.negative,
        'pending' => const Color(0xFFFFCC00),
        _ => AppTheme.positive,
      };

  @override
  Widget build(BuildContext context) {
    final calendar = context.read<AppState>().settings.calendar;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  formatMoney(item.amount),
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    color: AppTheme.title,
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
              ),
              if (canEdit)
                IconButton(
                  tooltip: 'ویرایش',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => showRecordWithdrawalDialog(
                    context,
                    existing: item,
                  ),
                  icon: const Icon(Icons.edit_outlined, size: 18),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  formatDisplayDate(item.createdAt, calendar),
                  textAlign: TextAlign.right,
                  style: const TextStyle(color: AppTheme.muted, fontSize: 12),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _statusColor.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(
                  item.statusLabel,
                  style: TextStyle(
                    color: _statusColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          if (item.note.isNotEmpty) ...[
            const SizedBox(height: 6),
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

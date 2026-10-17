import 'package:flutter/material.dart';
import 'package:invest/domain/models/bank_check.dart';
import 'package:invest/domain/services/check_ledger.dart';
import 'package:invest/domain/utils/dates.dart';
import 'package:invest/domain/utils/money.dart';
import 'package:invest/state/app_state.dart';
import 'package:invest/ui/layout/page_padding.dart';
import 'package:invest/ui/theme/app_theme.dart';
import 'package:invest/ui/widgets/app_date_picker.dart';
import 'package:invest/ui/widgets/user_error.dart';
import 'package:provider/provider.dart';

const _iranianBanks = <String>[
  'ملی',
  'ملت',
  'صادرات',
  'تجارت',
  'سپه',
  'پاسارگاد',
  'پارسیان',
  'سامان',
  'اقتصاد نوین',
  'کشاورزی',
  'مسکن',
  'رفاه',
  'آینده',
  'شهر',
  'دی',
  'سینا',
  'کارآفرین',
  'گردشگری',
  'ایران زمین',
  'پست بانک',
  'رسالت',
  'مهر ایران',
];

void openChecksPage(BuildContext context) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => const ChecksPage()),
  );
}

/// Compact cheque book on the dashboard.
class ChecksDashboardCard extends StatelessWidget {
  const ChecksDashboardCard({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final book = state.checkLedger;
    final calendar = state.settings.calendar;
    final next = book.nextDue;
    final overdue = book.overdueCount > 0;

    return Material(
      color: AppTheme.card,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: () => openChecksPage(context),
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: overdue
                  ? AppTheme.negative.withValues(alpha: 0.55)
                  : AppTheme.border,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.chevron_left_rounded,
                    color: AppTheme.muted,
                  ),
                  const Spacer(),
                  const Text(
                    'دفتر چک',
                    style: TextStyle(
                      color: AppTheme.title,
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    Icons.account_balance_wallet_outlined,
                    color: overdue ? AppTheme.negative : AppTheme.positive,
                    size: 20,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (state.checks.isEmpty)
                const Text(
                  'چک دریافتی و پرداختی را با مبلغ، تاریخ صدور و سررسید ثبت کنید.',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    color: AppTheme.muted,
                    fontSize: 12,
                    height: 1.4,
                  ),
                )
              else ...[
                Row(
                  children: [
                    Expanded(
                      child: _MiniStat(
                        label: 'بدهی',
                        value: formatCompactToman(book.debts),
                        hint: '${book.debtCount} چک پرداختی',
                        color: book.debts > 0
                            ? AppTheme.negative
                            : AppTheme.title,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _MiniStat(
                        label: 'دریافتی باز',
                        value: formatCompactToman(book.openReceivable),
                        hint: '${book.openReceivableCount} نزد صندوق',
                        color: book.openReceivable > 0
                            ? AppTheme.positive
                            : AppTheme.title,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  book.net >= 0
                      ? 'خالص دریافتنی ${formatCompactToman(book.net)}'
                      : 'خالص بدهی ${formatCompactToman(book.net.abs())}',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    color: book.net >= 0 ? AppTheme.positive : AppTheme.negative,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
                if (next != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    '${next.directionLabel} · ${next.identityLabel} · ${formatDisplayDate(next.dueDate, calendar)} · ${next.dueRelativeLabel()}',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      color: next.daysUntilDue() < 0
                          ? AppTheme.negative
                          : AppTheme.muted,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class ChecksPage extends StatefulWidget {
  const ChecksPage({super.key});

  @override
  State<ChecksPage> createState() => _ChecksPageState();
}

class _ChecksPageState extends State<ChecksPage> {
  CheckListFilter _filter = CheckListFilter.all;
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final book = state.checkLedger;
    final calendar = state.settings.calendar;
    final items = filterChecks(
      state.checks,
      _filter,
      query: _search.text,
    );

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('دفتر چک')),
        floatingActionButton: state.canMutate
            ? FloatingActionButton.extended(
                onPressed: () => openCheckEditor(context),
                icon: const Icon(Icons.add),
                label: const Text('ثبت چک'),
              )
            : null,
        floatingActionButtonLocation: FloatingActionButtonLocation.startFloat,
        body: ListView(
          padding: shellPagePadding(extraForFab: state.canMutate),
          children: [
            _BookSummary(book: book),
            if (book.overdueCount > 0) ...[
              const SizedBox(height: 10),
              _OverdueBanner(book: book),
            ],
            const SizedBox(height: 14),
            TextField(
              controller: _search,
              onChanged: (_) => setState(() {}),
              textAlign: TextAlign.right,
              decoration: const InputDecoration(
                hintText: 'جستجو: شماره، صیادی، بانک، طرف حساب',
                prefixIcon: Icon(Icons.search_rounded),
                isDense: true,
              ),
            ),
            const SizedBox(height: 10),
            _FilterRow(
              selected: _filter,
              onChanged: (v) => setState(() => _filter = v),
            ),
            const SizedBox(height: 12),
            if (items.isEmpty)
              _EmptyBook(
                hasAny: state.checks.isNotEmpty,
                canAdd: state.canMutate,
                onAdd: () => openCheckEditor(context),
              )
            else
              for (final item in items) ...[
                _CheckCard(
                  item: item,
                  calendar: calendar,
                  onTap: () => _openDetail(context, item),
                ),
                const SizedBox(height: 8),
              ],
          ],
        ),
      ),
    );
  }

  Future<void> _openDetail(BuildContext context, BankCheck item) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => _CheckDetailSheet(itemId: item.id),
    );
  }
}

class _BookSummary extends StatelessWidget {
  const _BookSummary({required this.book});
  final CheckLedger book;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _MiniStat(
                label: 'بدهی',
                value: formatCompactToman(book.debts),
                hint: '${book.debtCount} چک',
                color: book.debts > 0 ? AppTheme.negative : AppTheme.title,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _MiniStat(
                label: 'دریافتی باز',
                value: formatCompactToman(book.openReceivable),
                hint: '${book.openReceivableCount} چک',
                color: book.openReceivable > 0
                    ? AppTheme.positive
                    : AppTheme.title,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _MiniStat(
                label: 'سررسید ۷ روز',
                value: '${book.dueSoonCount}',
                hint: formatCompactToman(book.dueSoonAmount),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _MiniStat(
                label: 'برگشتی دریافتی',
                value: formatCompactToman(book.bouncedReceivable),
                hint: '${book.bouncedReceivableCount} مطالبه',
                color: book.bouncedReceivableCount > 0
                    ? const Color(0xFFE0C46A)
                    : AppTheme.title,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({
    required this.label,
    required this.value,
    required this.hint,
    this.color = AppTheme.title,
  });

  final String label;
  final String value;
  final String hint;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: AppTheme.muted,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w800,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            hint,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: AppTheme.muted, fontSize: 10),
          ),
        ],
      ),
    );
  }
}

class _OverdueBanner extends StatelessWidget {
  const _OverdueBanner({required this.book});
  final CheckLedger book;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: AppTheme.negative.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.negative.withValues(alpha: 0.35)),
      ),
      child: Text(
        '${book.overdueCount} چک از سررسید گذشته · ${formatMoney(book.overdueAmount)}',
        textAlign: TextAlign.right,
        style: const TextStyle(
          color: AppTheme.negative,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    );
  }
}

class _FilterRow extends StatelessWidget {
  const _FilterRow({required this.selected, required this.onChanged});

  final CheckListFilter selected;
  final ValueChanged<CheckListFilter> onChanged;

  static const _labels = <CheckListFilter, String>{
    CheckListFilter.all: 'همه',
    CheckListFilter.receivable: 'دریافتی',
    CheckListFilter.payable: 'پرداختی',
    CheckListFilter.due: 'سررسید',
    CheckListFilter.bounced: 'برگشتی',
    CheckListFilter.settled: 'تسویه‌شده',
  };

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      reverse: true,
      child: Row(
        children: [
          for (final e in _labels.entries)
            Padding(
              padding: const EdgeInsetsDirectional.only(start: 6),
              child: ChoiceChip(
                label: Text(e.value),
                selected: selected == e.key,
                onSelected: (_) => onChanged(e.key),
              ),
            ),
        ],
      ),
    );
  }
}

class _EmptyBook extends StatelessWidget {
  const _EmptyBook({
    required this.hasAny,
    required this.canAdd,
    required this.onAdd,
  });

  final bool hasAny;
  final bool canAdd;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 28, 8, 12),
      child: Column(
        children: [
          const Icon(
            Icons.account_balance_outlined,
            color: AppTheme.muted,
            size: 36,
          ),
          const SizedBox(height: 10),
          Text(
            hasAny ? 'چکی با این فیلتر نیست' : 'هنوز چکی ثبت نشده',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppTheme.title,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'مبلغ، تاریخ صدور، سررسید، شماره یا شناسه صیادی.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppTheme.muted, fontSize: 12),
          ),
          if (canAdd && !hasAny) ...[
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add),
              label: const Text('ثبت اولین چک'),
            ),
          ],
        ],
      ),
    );
  }
}

class _CheckCard extends StatelessWidget {
  const _CheckCard({
    required this.item,
    required this.calendar,
    required this.onTap,
  });

  final BankCheck item;
  final String calendar;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final overdue = item.isOpen && item.daysUntilDue() < 0;
    final tone = item.isPayable ? AppTheme.negative : AppTheme.positive;
    final who = item.counterparty.trim().isEmpty
        ? (item.bankName.trim().isEmpty ? 'بدون طرف حساب' : item.bankName)
        : item.counterparty;

    return Material(
      color: AppTheme.card,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: overdue
                  ? AppTheme.negative.withValues(alpha: 0.45)
                  : AppTheme.border,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Text(
                    formatMoney(item.amount),
                    style: const TextStyle(
                      color: AppTheme.title,
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
                  ),
                  const Spacer(),
                  _Tag(text: item.statusLabel, color: AppTheme.muted),
                  const SizedBox(width: 6),
                  _Tag(text: item.directionLabel, color: tone),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                who,
                textAlign: TextAlign.right,
                style: const TextStyle(
                  color: AppTheme.text,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${item.identityLabel}${item.bankName.trim().isEmpty ? '' : ' · ${item.bankName}'}',
                textAlign: TextAlign.right,
                style: const TextStyle(color: AppTheme.muted, fontSize: 12),
              ),
              const SizedBox(height: 4),
              Text(
                'سررسید ${formatDisplayDate(item.dueDate, calendar)} · ${item.dueRelativeLabel()}',
                textAlign: TextAlign.right,
                style: TextStyle(
                  color: overdue ? AppTheme.negative : AppTheme.muted,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.text, required this.color});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _CheckDetailSheet extends StatelessWidget {
  const _CheckDetailSheet({required this.itemId});
  final int? itemId;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    BankCheck? item;
    for (final c in state.checks) {
      if (c.id == itemId) item = c;
    }
    if (item == null) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Text('این چک دیگر در دفتر نیست.'),
      );
    }
    final check = item;
    final calendar = state.settings.calendar;
    final actions = _statusActions(check);

    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        0,
        16,
        16 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${check.directionLabel} · ${formatMoney(check.amount)}',
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: AppTheme.title,
                fontWeight: FontWeight.w800,
                fontSize: 18,
              ),
            ),
            const SizedBox(height: 8),
            _Fact('وضعیت', check.statusLabel),
            _Fact('سررسید',
                '${formatDisplayDate(check.dueDate, calendar)} · ${check.dueRelativeLabel()}'),
            _Fact('تاریخ صدور', formatDisplayDate(check.issueDate, calendar)),
            if (check.checkNumber.isNotEmpty)
              _Fact('شماره چک', check.checkNumber),
            if (check.sayadId.isNotEmpty) _Fact('شناسه صیادی', check.sayadId),
            if (check.bankName.isNotEmpty) _Fact('بانک', check.bankName),
            if (check.branch.isNotEmpty) _Fact('شعبه', check.branch),
            if (check.counterparty.isNotEmpty)
              _Fact(check.counterpartyLabel, check.counterparty),
            if (check.purpose.isNotEmpty) _Fact('بابت', check.purpose),
            if (check.note.isNotEmpty) _Fact('یادداشت', check.note),
            if (check.settledDate != null && check.settledDate!.isNotEmpty)
              _Fact(
                'تاریخ وضعیت',
                formatDisplayDate(check.settledDate, calendar),
              ),
            if (state.canMutate && actions.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.end,
                children: [
                  for (final action in actions)
                    OutlinedButton(
                      onPressed: () => _applyStatus(context, check, action),
                      child: Text(action.label),
                    ),
                ],
              ),
            ],
            if (state.canMutate) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  TextButton(
                    onPressed: () => _delete(context, state, check),
                    child: const Text(
                      'حذف',
                      style: TextStyle(color: AppTheme.negative),
                    ),
                  ),
                  const Spacer(),
                  ElevatedButton(
                    onPressed: () {
                      Navigator.pop(context);
                      openCheckEditor(context, existing: check);
                    },
                    child: const Text('ویرایش'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _applyStatus(
    BuildContext context,
    BankCheck check,
    _StatusAction action,
  ) async {
    final state = context.read<AppState>();
    try {
      final synced = await state.setCheckStatus(check, action.status);
      if (!context.mounted) return;
      if (!synced) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'وضعیت روی دستگاه ذخیره شد. با اتصال بعدی به سرور می‌رسد.',
            ),
          ),
        );
      }
      Navigator.pop(context);
    } catch (e) {
      if (context.mounted) showUserError(context, e);
    }
  }

  Future<void> _delete(
    BuildContext context,
    AppState state,
    BankCheck check,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف چک'),
        content: const Text(
          'این چک از دفتر حذف شود؟',
          textAlign: TextAlign.right,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('انصراف'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    try {
      final synced = await state.deleteCheck(check);
      if (!context.mounted) return;
      if (!synced) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'حذف روی دستگاه ماند. با اتصال بعدی از سرور هم پاک می‌شود.',
            ),
          ),
        );
      }
      Navigator.pop(context);
    } catch (e) {
      if (context.mounted) showUserError(context, e);
    }
  }
}

class _Fact extends StatelessWidget {
  const _Fact(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(color: AppTheme.text, fontSize: 13),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            label,
            style: const TextStyle(color: AppTheme.muted, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _StatusAction {
  const _StatusAction(this.label, this.status);
  final String label;
  final String status;
}

List<_StatusAction> _statusActions(BankCheck check) {
  if (check.status == checkStatusPending) {
    return [
      _StatusAction(check.isReceivable ? 'وصول شد' : 'پاس شد', checkStatusCleared),
      const _StatusAction('برگشت', checkStatusBounced),
      if (check.isReceivable)
        const _StatusAction('خرج شد', checkStatusEndorsed),
      const _StatusAction('باطل', checkStatusCancelled),
    ];
  }
  if (check.status == checkStatusBounced) {
    return [
      const _StatusAction('بازگشت به جریان', checkStatusPending),
      _StatusAction(
        check.isReceivable ? 'وصول شد' : 'پاس شد',
        checkStatusCleared,
      ),
      const _StatusAction('باطل', checkStatusCancelled),
    ];
  }
  return const [
    _StatusAction('بازگشت به جریان', checkStatusPending),
  ];
}

Future<void> openCheckEditor(BuildContext context, {BankCheck? existing}) {
  final state = context.read<AppState>();
  if (!state.canMutate) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('در حالت آفلاین فقط مشاهده ممکن است.'),
      ),
    );
    return Future.value();
  }
  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => CheckEditorPage(existing: existing),
    ),
  );
}

class CheckEditorPage extends StatefulWidget {
  const CheckEditorPage({super.key, this.existing});
  final BankCheck? existing;

  @override
  State<CheckEditorPage> createState() => _CheckEditorPageState();
}

class _CheckEditorPageState extends State<CheckEditorPage> {
  late String _direction;
  late String _issue;
  late String _due;
  late final TextEditingController _amount;
  late final TextEditingController _number;
  late final TextEditingController _sayad;
  late final TextEditingController _bank;
  late final TextEditingController _branch;
  late final TextEditingController _party;
  late final TextEditingController _purpose;
  late final TextEditingController _note;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _direction = e?.direction ?? checkDirectionReceivable;
    _issue = e?.issueDate.isNotEmpty == true ? e!.issueDate : todayIso();
    _due = e?.dueDate ?? '';
    _amount = TextEditingController(
      text: e == null ? '' : formatNumber(e.amount),
    );
    _number = TextEditingController(text: e?.checkNumber ?? '');
    _sayad = TextEditingController(text: e?.sayadId ?? '');
    _bank = TextEditingController(text: e?.bankName ?? '');
    _branch = TextEditingController(text: e?.branch ?? '');
    _party = TextEditingController(text: e?.counterparty ?? '');
    _purpose = TextEditingController(text: e?.purpose ?? '');
    _note = TextEditingController(text: e?.note ?? '');
  }

  @override
  void dispose() {
    _amount.dispose();
    _number.dispose();
    _sayad.dispose();
    _bank.dispose();
    _branch.dispose();
    _party.dispose();
    _purpose.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final calendar = state.settings.calendar;
    final editing = widget.existing != null;
    final partyLabel = _direction == checkDirectionReceivable
        ? 'صادرکننده'
        : 'در وجه';
    final horizon = DateTime(DateTime.now().year + 15, 12, 31);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Text(editing ? 'ویرایش چک' : 'ثبت چک'),
          actions: [
            TextButton(
              onPressed: _saving ? null : _save,
              child: Text(_saving ? '…' : 'ذخیره'),
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(
                  value: checkDirectionReceivable,
                  label: Text('دریافتی'),
                  icon: Icon(Icons.south_west_rounded),
                ),
                ButtonSegment(
                  value: checkDirectionPayable,
                  label: Text('پرداختی'),
                  icon: Icon(Icons.north_east_rounded),
                ),
              ],
              selected: {_direction},
              onSelectionChanged: (v) => setState(() => _direction = v.first),
            ),
            const SizedBox(height: 8),
            Text(
              _direction == checkDirectionReceivable
                  ? 'چکی که می‌گیرید؛ تا وصول، جزو دریافتی باز است.'
                  : 'چکی که صادر می‌کنید؛ تا پاس شدن، جزو بدهی است.',
              textAlign: TextAlign.right,
              style: const TextStyle(color: AppTheme.muted, fontSize: 12),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _amount,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              textAlign: TextAlign.right,
              decoration: const InputDecoration(labelText: 'مبلغ (تومان)'),
            ),
            AppDateTile(
              label: 'تاریخ صدور',
              isoDate: _issue,
              calendar: calendar,
              firstDate: DateTime(2000),
              lastDate: horizon,
              onChanged: (v) => setState(() => _issue = v),
            ),
            AppDateTile(
              label: 'تاریخ سررسید',
              isoDate: _due,
              calendar: calendar,
              firstDate: DateTime(2000),
              lastDate: horizon,
              onChanged: (v) => setState(() => _due = v),
            ),
            TextField(
              controller: _number,
              textAlign: TextAlign.right,
              decoration: const InputDecoration(labelText: 'شماره چک'),
            ),
            TextField(
              controller: _sayad,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.right,
              decoration: const InputDecoration(
                labelText: 'شناسه صیادی (۱۶ رقم)',
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _bank,
              textAlign: TextAlign.right,
              decoration: const InputDecoration(labelText: 'بانک'),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 36,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                reverse: true,
                itemCount: _iranianBanks.length,
                separatorBuilder: (_, __) => const SizedBox(width: 6),
                itemBuilder: (_, i) {
                  final bank = _iranianBanks[i];
                  return ActionChip(
                    label: Text(bank, style: const TextStyle(fontSize: 12)),
                    onPressed: () => setState(() => _bank.text = bank),
                  );
                },
              ),
            ),
            TextField(
              controller: _branch,
              textAlign: TextAlign.right,
              decoration: const InputDecoration(labelText: 'شعبه'),
            ),
            TextField(
              controller: _party,
              textAlign: TextAlign.right,
              decoration: InputDecoration(labelText: partyLabel),
            ),
            TextField(
              controller: _purpose,
              textAlign: TextAlign.right,
              decoration: const InputDecoration(labelText: 'بابت'),
            ),
            TextField(
              controller: _note,
              textAlign: TextAlign.right,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(labelText: 'یادداشت'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (_saving) return;
    final amount = parseFlexibleNumber(_amount.text);
    final draft = BankCheck(
      id: widget.existing?.id,
      direction: _direction,
      amount: amount ?? 0,
      issueDate: _issue,
      dueDate: _due,
      checkNumber: _number.text,
      sayadId: _sayad.text,
      bankName: _bank.text,
      branch: _branch.text,
      counterparty: _party.text,
      purpose: _purpose.text,
      note: _note.text,
      status: widget.existing?.status ?? checkStatusPending,
      settledDate: widget.existing?.settledDate,
      createdAt: widget.existing?.createdAt ?? '',
    );
    setState(() => _saving = true);
    try {
      final result = await context.read<AppState>().saveCheck(draft);
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.pop(context);
      if (!result.synced) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text(
              'چک روی دستگاه ذخیره شد. با اتصال بعدی به سرور فرستاده می‌شود.',
            ),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      showUserError(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

import 'package:flutter/material.dart';
import 'package:invest/data/biz_store.dart';
import 'package:invest/data/write_queue.dart';
import 'package:invest/domain/services/pwo_ledger.dart';
import 'package:invest/domain/utils/money.dart';
import 'package:invest/ui/pages/pwo_page.dart';
import 'package:invest/ui/theme/app_theme.dart';

class _MonthEditResult {
  const _MonthEditResult(this.body, {this.delete = false});
  final Map<String, dynamic> body;
  final bool delete;
}

String _amountText(double v) => v == 0 ? '' : formatNumber(v);

Future<bool> _guard(BuildContext context, Future<void> Function() op) async {
  try {
    await op();
    return true;
  } on WriteQueuedException catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.maybeOf(context)
          ?.showSnackBar(SnackBar(content: Text(e.toString())));
    }
    return true;
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.maybeOf(context)
          ?.showSnackBar(SnackBar(content: Text(e.toString())));
    }
    return false;
  }
}

/// Office-ops editor for one Jalali month. [allTradeProfit] is the realized
/// profit of every category in that month (property, gold, crypto, …);
/// the preview and «درآمد تکراری» rule use it together with the property
/// book’s net/gross.
Future<void> editBizMonth(
  BuildContext context,
  BizStore store,
  BizMonth m, {
  double allTradeProfit = 0,
  double allTradeGross = 0,
  int soldCount = 0,
  int boughtCount = 0,
  double boughtAmount = 0,
}) async {
  final res = await showDialog<_MonthEditResult>(
    context: context,
    builder: (_) => _MonthDialog(
      m: m,
      tradeProfit: allTradeProfit,
      tradeGross: allTradeGross != 0 ? allTradeGross : m.tradeGross,
      soldCount: soldCount > 0 ? soldCount : m.soldCount,
      boughtCount: boughtCount > 0 ? boughtCount : m.boughtCount,
      boughtAmount: boughtAmount > 0 ? boughtAmount : m.boughtAmount,
    ),
  );
  if (res == null || !context.mounted) return;
  if (res.delete) {
    await _guard(context, () => store.clearMonth(m.year, m.month));
  } else {
    await _guard(context, () => store.saveMonth(m.year, m.month, res.body));
  }
}

class _MonthDialog extends StatefulWidget {
  const _MonthDialog({
    required this.m,
    this.tradeProfit = 0,
    this.tradeGross = 0,
    this.soldCount = 0,
    this.boughtCount = 0,
    this.boughtAmount = 0,
  });
  final BizMonth m;
  final double tradeProfit;
  final double tradeGross;
  final int soldCount;
  final int boughtCount;
  final double boughtAmount;

  @override
  State<_MonthDialog> createState() => _MonthDialogState();
}

class _MonthDialogState extends State<_MonthDialog> {
  late final _staff = TextEditingController(text: _amountText(widget.m.staff));
  late final _ads = TextEditingController(text: _amountText(widget.m.ads));
  late final _income = TextEditingController(
    text: _amountText(widget.m.income),
  );
  late final _note = TextEditingController(text: widget.m.note);

  @override
  void initState() {
    super.initState();
    for (final c in [_staff, _ads, _income]) {
      c.addListener(_onFieldChanged);
    }
  }

  void _onFieldChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _staff.dispose();
    _ads.dispose();
    _income.dispose();
    _note.dispose();
    super.dispose();
  }

  Widget _f(
    TextEditingController c,
    String label,
    Key key, {
    bool num = true,
    int maxLines = 1,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: TextField(
      key: key,
      controller: c,
      maxLines: maxLines,
      keyboardType: num
          ? const TextInputType.numberWithOptions(decimal: true)
          : null,
      decoration: InputDecoration(labelText: label, isDense: true),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final m = widget.m;
    final inc = parseFlexibleNumber(_income.text) ?? 0;
    final stf = parseFlexibleNumber(_staff.text) ?? 0;
    final ads = parseFlexibleNumber(_ads.text) ?? 0;
    final dup = incomeDuplicatesTrades(
      inc,
      widget.tradeProfit,
      widget.tradeGross,
      allRealizedProfit: widget.tradeProfit,
    );
    final previewNet = (dup ? 0 : inc) - stf - m.pwo - ads + widget.tradeProfit;
    final tradeToman = formatMoney(widget.tradeProfit, forceToman: true);
    final pwoToman = formatMoney(m.pwo, forceToman: true);
    final netToman = formatMoney(previewNet, forceToman: true);
    final netUsd = CurrencyMode.isUsd ? ' (${formatMoney(previewNet)})' : '';

    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title: Text('برج ${m.month} · ${pwoMonthNames[m.month - 1]} ${m.year}'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _f(_income, 'درآمد (تومان)', const ValueKey('biz-m-income')),
              if (widget.soldCount > 0 || widget.boughtCount > 0)
                Container(
                  key: const ValueKey('biz-m-trades-info'),
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppTheme.border),
                  ),
                  child: Text(
                    [
                      if (widget.soldCount > 0)
                        'سود ${widget.soldCount} معاملهٔ بسته‌شدهٔ این ماه ($tradeToman) خودکار به خالص اضافه می‌شود؛ آن را در «درآمد» وارد نکنید.',
                      if (widget.boughtCount > 0)
                        'خرید / سرمایه‌گذاری این ماه: ${widget.boughtCount} مورد · ${formatMoney(widget.boughtAmount, forceToman: true)} (در خالص حساب نمی‌شود).',
                    ].join('\n'),
                    textAlign: TextAlign.right,
                    style: const TextStyle(color: AppTheme.muted, fontSize: 12),
                  ),
                ),
              if (dup)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    key: const ValueKey('biz-m-clear-dup'),
                    style: TextButton.styleFrom(
                      foregroundColor: AppTheme.negative,
                    ),
                    onPressed: () => setState(() => _income.text = ''),
                    icon: const Icon(
                      Icons.cleaning_services_outlined,
                      size: 16,
                    ),
                    label: const Text(
                      'درآمد تکراری است (همان سود معاملات) — صفر کن',
                      textAlign: TextAlign.right,
                    ),
                  ),
                ),
              _f(_staff, 'کارمندان (تومان)', const ValueKey('biz-m-staff')),
              _f(
                _ads,
                'دیوار - تبلیغات دفتر (تومان)',
                const ValueKey('biz-m-ads'),
              ),
              _f(
                _note,
                'یادداشت ماه',
                const ValueKey('biz-m-note'),
                num: false,
                maxLines: 2,
              ),
              Container(
                key: const ValueKey('biz-m-net-preview'),
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppTheme.border),
                ),
                child: Text(
                  'خالص ماه: $netToman$netUsd${widget.tradeProfit != 0 ? ' (با سود معاملات)' : ''}',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    color: previewNet < 0
                        ? AppTheme.negative
                        : AppTheme.positive,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () {
                    final nav = Navigator.of(context);
                    nav.pop();
                    nav.push(
                      MaterialPageRoute(builder: (_) => const PwoPage()),
                    );
                  },
                  child: Text(
                    'PWO این ماه: $pwoToman\nویرایش در بخش PWO',
                    textAlign: TextAlign.right,
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          if (m.hasOps)
            TextButton(
              onPressed: () => Navigator.pop(
                context,
                const _MonthEditResult({}, delete: true),
              ),
              child: const Text(
                'پاک کردن ماه',
                style: TextStyle(color: AppTheme.negative),
              ),
            ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('انصراف'),
          ),
          FilledButton(
            key: const ValueKey('biz-m-save'),
            onPressed: () {
              final nextNote = _note.text.trim();
              final body = <String, dynamic>{
                'staff': parseFlexibleNumber(_staff.text) ?? 0,
                'ads': parseFlexibleNumber(_ads.text) ?? 0,
                'income': parseFlexibleNumber(_income.text) ?? 0,
                if (nextNote != widget.m.note) 'note': nextNote,
              };
              Navigator.pop(context, _MonthEditResult(body));
            },
            child: const Text('ذخیره'),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:invest/domain/models/gold_cash_entry.dart';
import 'package:invest/domain/utils/dates.dart';
import 'package:invest/domain/utils/gold_number_input.dart';
import 'package:invest/state/app_state.dart';
import 'package:invest/ui/gold/gold_format.dart';
import 'package:invest/ui/gold/gold_input.dart';
import 'package:invest/ui/theme/app_theme.dart';
import 'package:invest/ui/widgets/app_date_picker.dart';
import 'package:invest/ui/widgets/dashboard_kit.dart';
import 'package:invest/ui/widgets/user_error.dart';
import 'package:provider/provider.dart';

/// «نقد صندوق»: deposit, withdraw or set the balance of the gold fund cash.
Future<void> showGoldCashSheet(BuildContext context, {String kind = GoldCashKind.deposit}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    backgroundColor: kSheetBg,
    builder: (ctx) => Directionality(
      textDirection: TextDirection.rtl,
      child: GoldCashSheet(initialKind: kind),
    ),
  );
}

class GoldCashSheet extends StatefulWidget {
  const GoldCashSheet({super.key, this.initialKind = GoldCashKind.deposit});
  final String initialKind;

  @override
  State<GoldCashSheet> createState() => _GoldCashSheetState();
}

class _GoldCashSheetState extends State<GoldCashSheet> {
  late String _kind = widget.initialKind == GoldCashKind.opening ? GoldCashKind.deposit : widget.initialKind;
  final _amount = TextEditingController();
  final _note = TextEditingController();
  String _date = todayIso();
  bool _mirror = false;
  bool _busy = false;

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final cash = state.goldFundCash;
    final v = parseGoldToman(_amount.text) ?? 0;
    final withdraw = _kind == GoldCashKind.withdraw;
    final adjust = _kind == GoldCashKind.adjust;
    final after = switch (_kind) {
      GoldCashKind.withdraw => cash - v,
      GoldCashKind.adjust => v,
      _ => cash + v,
    };
    String? error;
    if (withdraw && v > cash + 0.5) error = 'از مانده (${gToman(cash)}) بیشتر است.';
    if (adjust && _amount.text.trim().isNotEmpty && (v - cash).abs() < 0.5) error = 'مانده همین است.';
    final valid = error == null && (adjust ? _amount.text.trim().isNotEmpty : v >= 1);
    final verb = switch (_kind) {
      GoldCashKind.withdraw => 'برداشت',
      GoldCashKind.adjust => 'تنظیم مانده',
      _ => 'واریز',
    };
    final chips = <(String, double)>[
      ('۱۰ م', 10e6),
      ('۵۰ م', 50e6),
      ('۱۰۰ م', 100e6),
      if (withdraw && cash > 0) ('نصف', (cash / 2).floorToDouble()),
      if (withdraw && cash > 0) ('همه', cash.floorToDouble()),
    ];
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.92),
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Flexible(
            child: SingleChildScrollView(
              key: const ValueKey('gcs-scroll'),
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  const Expanded(
                    child:
                        Text('نقد صندوق', style: TextStyle(color: AppTheme.title, fontSize: 15, fontWeight: FontWeight.w900)),
                  ),
                  Flexible(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppTheme.positive.withValues(alpha: 0.45)),
                      ),
                      child: GFit('مانده ${gToman(cash)}',
                          key: const ValueKey('gcs-balance'),
                          style: const TextStyle(color: AppTheme.positive, fontSize: 11, fontWeight: FontWeight.w800)),
                    ),
                  ),
                ]),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<String>(
                    key: const ValueKey('gcs-kind'),
                    showSelectedIcon: false,
                    style: SegmentedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                    ),
                    segments: const [
                      ButtonSegment(
                          value: GoldCashKind.deposit, label: FittedBox(fit: BoxFit.scaleDown, child: Text('واریز'))),
                      ButtonSegment(
                          value: GoldCashKind.withdraw, label: FittedBox(fit: BoxFit.scaleDown, child: Text('برداشت'))),
                      ButtonSegment(
                          value: GoldCashKind.adjust, label: FittedBox(fit: BoxFit.scaleDown, child: Text('تنظیم مانده'))),
                    ],
                    selected: {_kind},
                    onSelectionChanged: (s) => setState(() {
                      _kind = s.first;
                      _amount.clear();
                    }),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  key: const ValueKey('gcs-amount'),
                  controller: _amount,
                  keyboardType: TextInputType.number,
                  inputFormatters: const [GoldTomanFormatter()],
                  textDirection: TextDirection.ltr,
                  textAlign: TextAlign.right,
                  style: const TextStyle(color: AppTheme.title, fontSize: 18, fontWeight: FontWeight.w900),
                  decoration: InputDecoration(
                    labelText: adjust ? 'مانده درست (تومان)' : 'مبلغ (تومان)',
                    helperText: v > 0 ? gCompact(v) : (adjust ? 'مانده واقعی نقد صندوق را وارد کنید' : null),
                    errorText: error,
                    isDense: true,
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                if (!adjust) ...[
                  const SizedBox(height: 6),
                  Wrap(spacing: 6, runSpacing: 4, children: [
                    for (final (l, a) in chips)
                      ChoiceChip(
                        label: Text(l, style: const TextStyle(fontSize: 11.5)),
                        selected: (v - a).abs() < 0.5 && v > 0,
                        visualDensity: VisualDensity.compact,
                        onSelected: (_) => setState(() => _amount.text = goldTomanText(a)),
                      ),
                  ]),
                ],
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(
                    child: InkWell(
                      key: const ValueKey('gcs-date'),
                      onTap: () async {
                        final iso = await pickAppDate(context, calendar: state.settings.calendar, initialIso: _date);
                        if (iso != null) setState(() => _date = iso);
                      },
                      child: InputDecorator(
                        decoration: const InputDecoration(labelText: 'تاریخ', isDense: true),
                        child: Text(formatDisplayDate(_date, state.settings.calendar),
                            maxLines: 1, style: const TextStyle(fontSize: 13)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: TextField(
                      key: const ValueKey('gcs-note'),
                      controller: _note,
                      maxLength: 120,
                      decoration: const InputDecoration(labelText: 'یادداشت', isDense: true, counterText: ''),
                    ),
                  ),
                ]),
                if (withdraw) ...[
                  const SizedBox(height: 10),
                  Material(
                    color: AppTheme.bg,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: const BorderSide(color: AppTheme.border),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: SwitchListTile(
                      key: const ValueKey('gcs-mirror'),
                      value: _mirror,
                      onChanged: (x) => setState(() => _mirror = x),
                      dense: true,
                      title: const Text('در تب «نقدینگی» هم به‌عنوان برداشت سود ثبت شود',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                      subtitle: Text('از سقف برداشت سالانه کم می‌شود', style: mutedStyle(10.5)),
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                Container(
                  key: const ValueKey('gcs-after'),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppTheme.positive.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.positive.withValues(alpha: 0.25)),
                  ),
                  child: Row(children: [
                    Expanded(child: Text('مانده بعد از $verb', style: mutedStyle(12))),
                    Flexible(
                      child: GFit(gToman(after),
                          align: AlignmentDirectional.centerEnd,
                          style: TextStyle(
                              color: after < 0 ? AppTheme.negative : AppTheme.title,
                              fontSize: 13,
                              fontWeight: FontWeight.w900)),
                    ),
                  ]),
                ),
                if (adjust && valid)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text('یک ردیف «تنظیم مانده» با اختلاف ${gSigned(v - cash)} تومان ثبت می‌شود.',
                        style: mutedStyle(10.5)),
                  ),
              ]),
            ),
          ),
          // Pinned like the calculator's footer: always visible, above the
          // system nav bar and on the keyboard when it is up.
          Container(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 16 + gSafeBottom(context)),
            decoration: const BoxDecoration(
              color: kSheetBg,
              border: Border(top: BorderSide(color: AppTheme.border)),
            ),
            child: FilledButton(
              key: const ValueKey('gcs-save'),
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, 48),
                backgroundColor: AppTheme.positive,
                foregroundColor: AppTheme.bg,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: valid && !_busy && state.canMutate ? () => _save(state, v) : null,
              child: _busy
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        adjust ? 'ثبت مانده ${gToman(v)} تومان' : 'ثبت $verb ${v > 0 ? '${gToman(v)} تومان' : ''}',
                        maxLines: 1,
                      ),
                    ),
            ),
          ),
        ]),
      ),
    );
  }

  Future<void> _save(AppState state, double v) async {
    setState(() => _busy = true);
    try {
      await state.addGoldCashEntry(
        kind: _kind,
        amount: v,
        date: _date,
        note: _note.text,
        mirrorWithdrawal: _mirror,
      );
      if (!mounted) return;
      final messenger = ScaffoldMessenger.maybeOf(context);
      Navigator.of(context).maybePop();
      messenger?.showSnackBar(const SnackBar(behavior: SnackBarBehavior.floating, content: Text('نقد صندوق ثبت شد.')));
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      showUserError(context, e);
    }
  }
}

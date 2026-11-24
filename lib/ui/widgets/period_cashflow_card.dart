import 'dart:async';

import 'package:flutter/material.dart';
import 'package:invest/data/bank_sms_store.dart';
import 'package:invest/data/pwo_store.dart';
import 'package:invest/domain/services/bank_sms_parser.dart';
import 'package:invest/domain/services/period_cashflow.dart';
import 'package:invest/domain/utils/dates.dart';
import 'package:invest/domain/utils/money.dart';
import 'package:invest/state/app_state.dart';
import 'package:invest/ui/theme/app_theme.dart';
import 'package:invest/ui/widgets/dashboard_kit.dart';
import 'package:provider/provider.dart';
import 'package:shamsi_date/shamsi_date.dart';

/// Compact day/month/year in/out totals from bank SMS and recorded
/// transactions, shown at the top of the withdrawals tab.
class PeriodCashflowCard extends StatefulWidget {
  const PeriodCashflowCard({
    super.key,
    this.now,
    this.smsOverride,
    this.smsUnavailableOverride,
    this.pwoOverride,
  });

  /// Clock for tests; defaults to the device time.
  final DateTime? now;

  /// When set, inbox/history are not read (unit/widget tests).
  final List<BankSmsItem>? smsOverride;
  final bool? smsUnavailableOverride;
  final PwoStore? pwoOverride;

  @override
  State<PeriodCashflowCard> createState() => _PeriodCashflowCardState();
}

class _PeriodCashflowCardState extends State<PeriodCashflowCard> {
  CashflowPeriod _period = CashflowPeriod.month;
  List<BankSmsItem> _sms = const [];
  bool _smsUnavailable = false;
  bool _inboxUnreadable = false;
  String? _smsError;

  /// False until the first SMS load finishes: no «unavailable» flash.
  bool _loaded = false;

  /// Year-start the loaded SMS cover. The store is always asked for the whole
  /// Jalali year, so switching روز/ماه/سال never rescans.
  int _loadedFrom = -1;
  bool _reloading = false;
  bool _again = false;
  Timer? _midnight;
  AppLifecycleListener? _life;

  DateTime get _now => widget.now ?? DateTime.now();

  @override
  void initState() {
    super.initState();
    BankSmsStore.instance.addListener(_onSmsStore);
    _life = AppLifecycleListener(onResume: () {
      if (mounted) _reloadSms();
    });
    _armMidnight();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _reloadSms();
    });
  }

  @override
  void didUpdateWidget(covariant PeriodCashflowCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.smsOverride != widget.smsOverride ||
        oldWidget.smsUnavailableOverride != widget.smsUnavailableOverride ||
        oldWidget.now != widget.now) {
      _reloadSms();
    }
  }

  @override
  void dispose() {
    BankSmsStore.instance.removeListener(_onSmsStore);
    _midnight?.cancel();
    _life?.dispose();
    super.dispose();
  }

  void _onSmsStore() {
    if (mounted) _reloadSms();
  }

  /// Re-render (and reload) just after local midnight: the day changes, and
  /// on 1 Farvardin the year does too.
  void _armMidnight() {
    _midnight?.cancel();
    if (widget.now != null) return;
    final n = DateTime.now();
    final next = DateTime(n.year, n.month, n.day + 1, 0, 0, 5);
    _midnight = Timer(next.difference(n), () {
      if (!mounted) return;
      setState(() {});
      _reloadSms();
      _armMidnight();
    });
  }

  Future<void> _reloadSms() async {
    if (widget.smsOverride != null || widget.smsUnavailableOverride != null) {
      if (!mounted) return;
      setState(() {
        _sms = widget.smsOverride ?? const [];
        _smsUnavailable = widget.smsUnavailableOverride ?? false;
        _loaded = true;
      });
      return;
    }
    // A reload while one runs is not dropped: it runs again afterwards with
    // the then-current period / clock.
    if (_reloading) {
      _again = true;
      return;
    }
    _reloading = true;
    try {
      do {
        _again = false;
        await _loadOnce();
      } while (_again && mounted);
    } finally {
      _reloading = false;
    }
  }

  Future<void> _loadOnce() async {
    final store = BankSmsStore.instance;
    String? error;
    try {
      await store.load();
      if (!store.capsChecked) await store.refreshCaps();
    } catch (e) {
      error = '${e.runtimeType}';
    }
    if (!mounted) return;
    final from =
        cashflowPeriodStart(CashflowPeriod.year, _now).millisecondsSinceEpoch;
    final unavailable = !store.smsAvailable;
    var moves = const <BankSmsItem>[];
    if (!unavailable) {
      try {
        moves = await store
            .movementsSince(DateTime.fromMillisecondsSinceEpoch(from));
        error ??= store.cashflowError;
      } catch (e) {
        error = '${e.runtimeType}';
      }
    }
    if (!mounted) return;
    setState(() {
      _smsUnavailable = unavailable;
      _inboxUnreadable = !unavailable && store.smsInboxUnreadable;
      _smsError = unavailable ? null : error;
      _sms = moves;
      _loadedFrom = from;
      _loaded = true;
    });
  }

  void _select(CashflowPeriod period) {
    if (_period == period) return;
    setState(() => _period = period);
    // Data already covers the whole year; reload only if the year moved.
    final from =
        cashflowPeriodStart(CashflowPeriod.year, _now).millisecondsSinceEpoch;
    if (from != _loadedFrom && widget.smsOverride == null) _reloadSms();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final pwo = widget.pwoOverride ?? PwoStore.instance;
    return ListenableBuilder(
      listenable: pwo,
      builder: (context, _) {
        final flow = computePeriodCashflow(
          period: _period,
          now: _now,
          sms: [for (final it in _sms) CashflowSms.fromItem(it)],
          withdrawals: state.withdrawals,
          checks: state.checks,
          pwo: pwo.ledger,
          smsUnavailable: _smsUnavailable || !_loaded,
        );
        return _CardBody(
          period: _period,
          now: _now,
          flow: flow,
          showUnavailable: _loaded && _smsUnavailable,
          inboxUnreadable: _inboxUnreadable,
          smsError: _smsError,
          onSelect: _select,
        );
      },
    );
  }
}

class _CardBody extends StatelessWidget {
  const _CardBody({
    required this.period,
    required this.now,
    required this.flow,
    required this.onSelect,
    this.showUnavailable = false,
    this.inboxUnreadable = false,
    this.smsError,
  });

  final CashflowPeriod period;
  final DateTime now;
  final PeriodCashflow flow;
  final ValueChanged<CashflowPeriod> onSelect;
  final bool showUnavailable;
  final bool inboxUnreadable;
  final String? smsError;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('period-cashflow-card'),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 2,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.transparent,
                  AppTheme.positive,
                  AppTheme.negative,
                  Colors.transparent,
                ],
                stops: [0, 0.35, 0.65, 1],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 11, 12, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'گردش پول',
                            style: TextStyle(
                              color: AppTheme.muted,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 1),
                          Text(
                            fa(cashflowPeriodCaption(period, now)),
                            key: const ValueKey('period-cashflow-caption'),
                            style: const TextStyle(
                              color: AppTheme.title,
                              fontSize: 13.5,
                              fontWeight: FontWeight.w800,
                              height: 1.2,
                            ),
                          ),
                        ],
                      ),
                    ),
                    _Segments(period: period, onSelect: onSelect),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _Tile(
                        label: 'ورودی',
                        color: AppTheme.positive,
                        total: flow.inflow,
                        sms: flow.smsIn,
                        tx: flow.txIn,
                        showSms: !flow.smsUnavailable,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _Tile(
                        label: 'خروجی',
                        color: AppTheme.negative,
                        total: flow.outflow,
                        sms: flow.smsOut,
                        tx: flow.txOut,
                        showSms: !flow.smsUnavailable,
                      ),
                    ),
                  ],
                ),
                if (showUnavailable)
                  _Note(
                    'پیامک در دسترس نیست',
                    key: const ValueKey('period-cashflow-sms-off'),
                  ),
                if (inboxUnreadable)
                  _Note(
                    'فقط پیامک‌های دریافت‌شده هنگام باز بودن برنامه؛ دسترسی خواندن پیامک خاموش است',
                    key: const ValueKey('period-cashflow-sms-partial'),
                  ),
                if (smsError != null)
                  _Note(
                    'خواندن پیامک‌ها ناموفق بود؛ اعداد پیامک ممکن است ناقص باشد',
                    key: const ValueKey('period-cashflow-sms-error'),
                    color: AppTheme.negative,
                  ),
                if (flow.pwoMonthOnly)
                  _Note(
                    'برداشت‌های PWO روز ندارند و فقط در «ماه» و «سال» شمرده می‌شوند',
                    key: const ValueKey('period-cashflow-pwo-day'),
                  ),
                if (flow.duplicates.isNotEmpty)
                  _DupLine(pairs: flow.duplicates),
                const SizedBox(height: 8),
                const Divider(height: 1, color: AppTheme.border),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        cashflowNetLabel(period),
                        style: const TextStyle(
                          color: AppTheme.title,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    Text(
                      _money(flow.net, signed: true),
                      key: const ValueKey('period-cashflow-net'),
                      style: TextStyle(
                        color: flow.net > 0
                            ? AppTheme.positive
                            : flow.net < 0
                                ? AppTheme.negative
                                : AppTheme.title,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Segments extends StatelessWidget {
  const _Segments({required this.period, required this.onSelect});
  final CashflowPeriod period;
  final ValueChanged<CashflowPeriod> onSelect;

  @override
  Widget build(BuildContext context) {
    Widget seg(CashflowPeriod value, String label) {
      final on = period == value;
      // 40×40 tap target around a compact pill; read as a selectable button.
      return Semantics(
        button: true,
        selected: on,
        label: 'گردش پول $label',
        excludeSemantics: true,
        onTap: () => onSelect(value),
        child: InkWell(
          key: ValueKey('period-cashflow-${value.name}'),
          borderRadius: BorderRadius.circular(7),
          onTap: () => onSelect(value),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: on ? AppTheme.accent : Colors.transparent,
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: on ? Colors.white : AppTheme.muted,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      decoration: BoxDecoration(
        color: AppTheme.bg,
        border: Border.all(color: AppTheme.border),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          seg(CashflowPeriod.day, 'روز'),
          seg(CashflowPeriod.month, 'ماه'),
          seg(CashflowPeriod.year, 'سال'),
        ],
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.label,
    required this.color,
    required this.total,
    required this.sms,
    required this.tx,
    required this.showSms,
  });

  final String label;
  final Color color;
  final double total;
  final double sms;
  final double tx;
  final bool showSms;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(9, 8, 9, 7),
      decoration: BoxDecoration(
        color: const Color(0xAA0F1A15),
        border: Border.all(color: AppTheme.border),
        borderRadius: BorderRadius.circular(11),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 5),
              Text(
                label,
                style: const TextStyle(
                  color: AppTheme.muted,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            // Direction is in the label and colour: no «+» on خروجی.
            _money(total),
            key: ValueKey('period-cashflow-total-$label'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: color,
              fontSize: 15.5,
              fontWeight: FontWeight.w800,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            showSms
                ? 'پیامک ${_money(sms)}\nتراکنش ${_money(tx)}'
                : 'تراکنش ${_money(tx)}',
            style: const TextStyle(
              color: AppTheme.muted,
              fontSize: 10,
              fontWeight: FontWeight.w600,
              height: 1.55,
            ),
          ),
        ],
      ),
    );
  }
}

String _money(num value, {bool signed = false}) {
  if (value == 0) return fa(formatCompactToman(0));
  if (signed) return faSigned(formatCompactToman(value, showSign: true));
  return fa(formatCompactToman(value));
}

class _Note extends StatelessWidget {
  const _Note(this.text, {super.key, this.color});
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Text(
        text,
        style: mutedStyle(10).copyWith(color: color),
      ),
    );
  }
}

/// «احتمال تکرار: N مورد» — tap to see the SMS / app-row pairs.
class _DupLine extends StatelessWidget {
  const _DupLine({required this.pairs});
  final List<CashflowDupPair> pairs;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      child: InkWell(
        key: const ValueKey('period-cashflow-dups'),
        onTap: () => _show(context),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 32),
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: Text(
              fa('احتمال تکرار: ${pairs.length} مورد'),
              style: mutedStyle(10, FontWeight.w700)
                  .copyWith(decoration: TextDecoration.underline),
            ),
          ),
        ),
      ),
    );
  }

  void _show(BuildContext context) {
    String day(DateTime d) {
      final j = Jalali.fromDateTime(d);
      return fa('${j.day} ${jalaliMonthNamesFa[j.month - 1]}');
    }

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppTheme.card,
      builder: (ctx) => SafeArea(
        child: ListView(
          key: const ValueKey('period-cashflow-dups-sheet'),
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          children: [
            const Text(
              'احتمال تکرار',
              style: TextStyle(
                color: AppTheme.title,
                fontSize: 14,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'هم‌مبلغ و هم‌جهت در یک روز یا روز کناری؛ هر دو حساب شده‌اند.',
              style: mutedStyle(11),
            ),
            const SizedBox(height: 8),
            for (final p in pairs)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text(
                  '${p.isIn ? 'ورودی' : 'خروجی'} ${_money(p.toman)}\n'
                  'پیامک ${p.smsBank} · ${day(p.smsAt)}\n'
                  '${p.rowLabel} · ${day(p.rowAt)}',
                  style: const TextStyle(
                    color: AppTheme.title,
                    fontSize: 12,
                    height: 1.6,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

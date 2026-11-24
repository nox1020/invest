import 'package:flutter/material.dart';
import 'package:invest/data/bank_sms_store.dart';
import 'package:invest/data/pwo_store.dart';
import 'package:invest/domain/services/bank_sms_parser.dart';
import 'package:invest/domain/services/period_cashflow.dart';
import 'package:invest/domain/utils/money.dart';
import 'package:invest/state/app_state.dart';
import 'package:invest/ui/theme/app_theme.dart';
import 'package:invest/ui/widgets/dashboard_kit.dart';
import 'package:provider/provider.dart';

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
  bool _smsUnavailable = true;
  bool _reloading = false;

  DateTime get _now => widget.now ?? DateTime.now();

  @override
  void initState() {
    super.initState();
    BankSmsStore.instance.addListener(_onSmsStore);
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
    super.dispose();
  }

  void _onSmsStore() {
    if (mounted) _reloadSms();
  }

  Future<void> _reloadSms() async {
    if (widget.smsOverride != null || widget.smsUnavailableOverride != null) {
      if (!mounted) return;
      setState(() {
        _sms = widget.smsOverride ?? const [];
        _smsUnavailable = widget.smsUnavailableOverride ?? false;
      });
      return;
    }
    if (_reloading) return;
    _reloading = true;
    try {
      final store = BankSmsStore.instance;
      try {
        await store.load();
        if (!store.capsChecked) await store.refreshCaps();
      } catch (_) {}
      if (!mounted) return;
      final unavailable = !store.smsAvailable;
      var moves = <BankSmsItem>[];
      if (!unavailable) {
        try {
          moves = await store.movementsSince(
            cashflowPeriodStart(_period, _now),
          );
        } catch (_) {}
      }
      if (!mounted) return;
      setState(() {
        _smsUnavailable = unavailable;
        _sms = moves;
      });
    } finally {
      _reloading = false;
    }
  }

  void _select(CashflowPeriod period) {
    if (_period == period) return;
    setState(() => _period = period);
    _reloadSms();
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
          smsUnavailable: _smsUnavailable,
        );
        return _CardBody(
          period: _period,
          now: _now,
          flow: flow,
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
  });

  final CashflowPeriod period;
  final DateTime now;
  final PeriodCashflow flow;
  final ValueChanged<CashflowPeriod> onSelect;

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
                if (flow.smsUnavailable) ...[
                  const SizedBox(height: 8),
                  Text(
                    'پیامک در دسترس نیست',
                    key: const ValueKey('period-cashflow-sms-off'),
                    style: mutedStyle(10),
                  ),
                ],
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
      return GestureDetector(
        key: ValueKey('period-cashflow-${value.name}'),
        onTap: () => onSelect(value),
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
      );
    }

    return Container(
      padding: const EdgeInsets.all(2),
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
            _money(total, signed: true),
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

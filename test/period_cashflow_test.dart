import 'package:flutter_test/flutter_test.dart';
import 'package:invest/domain/models/bank_check.dart';
import 'package:invest/domain/models/check_payment.dart';
import 'package:invest/domain/models/withdrawal.dart';
import 'package:invest/domain/services/period_cashflow.dart';
import 'package:invest/domain/services/pwo_ledger.dart';

// 3 Azar 1405.
final now = DateTime(2026, 11, 24, 15, 30);
// 30 Aban 1405 (last day of the previous Jalali month).
final lastOfAban = DateTime(2026, 11, 21, 10);
// 1 Farvardin 1405 (year start).
final firstOfYear = DateTime(2026, 3, 21, 8);
// 30 Esfand 1404 (day before year start).
final lastOfPrevYear = DateTime(2026, 3, 20, 18);

CashflowSms smsMove(
  DateTime at,
  double toman, {
  bool isIn = false,
  String tag = '',
  String bank = 'بانک ملت',
}) =>
    CashflowSms(at: at, toman: toman, isIn: isIn, tag: tag, bank: bank);

BankCheck cheque({
  String direction = checkDirectionReceivable,
  double amount = 1000,
  String status = checkStatusPending,
  String? settled,
  String? archived,
  List<CheckPayment> payments = const [],
  String note = '',
  String due = '2026-11-24',
}) {
  return BankCheck(
    id: 1,
    direction: direction,
    amount: amount,
    issueDate: '2026-10-01',
    dueDate: due,
    checkNumber: '101',
    status: status,
    settledDate: settled,
    archivedAt: archived,
    payments: payments,
    note: note,
  );
}

PeriodCashflow flow({
  CashflowPeriod period = CashflowPeriod.day,
  List<CashflowSms> sms = const [],
  List<Withdrawal> withdrawals = const [],
  List<BankCheck> checks = const [],
  PwoLedger? pwo,
  bool smsUnavailable = false,
}) {
  return computePeriodCashflow(
    period: period,
    now: now,
    sms: sms,
    withdrawals: withdrawals,
    checks: checks,
    pwo: pwo ?? PwoLedger(people: [], months: {}),
    smsUnavailable: smsUnavailable,
  );
}

void main() {
  test('period boundaries: last of month, year start, previous year', () {
    expect(isInCashflowPeriod(now, CashflowPeriod.day, now), isTrue);
    expect(isInCashflowPeriod(lastOfAban, CashflowPeriod.day, now), isFalse);
    expect(isInCashflowPeriod(lastOfAban, CashflowPeriod.month, now), isFalse);
    expect(isInCashflowPeriod(lastOfAban, CashflowPeriod.year, now), isTrue);

    expect(isInCashflowPeriod(firstOfYear, CashflowPeriod.day, now), isFalse);
    expect(isInCashflowPeriod(firstOfYear, CashflowPeriod.month, now), isFalse);
    expect(isInCashflowPeriod(firstOfYear, CashflowPeriod.year, now), isTrue);

    expect(
        isInCashflowPeriod(lastOfPrevYear, CashflowPeriod.day, now), isFalse);
    expect(
        isInCashflowPeriod(lastOfPrevYear, CashflowPeriod.month, now), isFalse);
    expect(
        isInCashflowPeriod(lastOfPrevYear, CashflowPeriod.year, now), isFalse);

    expect(
        cashflowPeriodStart(CashflowPeriod.day, now), DateTime(2026, 11, 24));
    expect(
        cashflowPeriodStart(CashflowPeriod.month, now).isBefore(now) ||
            cashflowPeriodStart(CashflowPeriod.month, now) ==
                DateTime(2026, 11, 22),
        isTrue);
    expect(
        cashflowPeriodStart(CashflowPeriod.year, now), DateTime(2026, 3, 21));
  });

  test('Jalali captions', () {
    expect(cashflowPeriodCaption(CashflowPeriod.day, now), 'امروز 3 آذر 1405');
    expect(cashflowPeriodCaption(CashflowPeriod.month, now), 'آذر 1405');
    expect(cashflowPeriodCaption(CashflowPeriod.year, now), '1405');
  });

  test('SMS in and out plus rejected SMS still count', () {
    final r = flow(sms: [
      smsMove(now, 5000000, isIn: true),
      smsMove(now, 3000000),
      smsMove(lastOfAban, 8000000), // rejected last month: not today
    ]);
    expect(r.smsIn, 5000000);
    expect(r.smsOut, 3000000);
    expect(r.txIn, 0);
    expect(r.inflow, 5000000);
    expect(r.outflow, 3000000);
    expect(r.net, 2000000);

    final year = flow(period: CashflowPeriod.year, sms: [
      smsMove(now, 5000000, isIn: true),
      smsMove(now, 3000000),
      smsMove(lastOfAban, 8000000),
    ]);
    expect(year.smsOut, 11000000);
    expect(year.smsIn, 5000000);
  });

  test('tagged withdrawal is skipped; untagged same-day amounts both count',
      () {
    const tag = '#abcd1234';
    final tagged = flow(
      sms: [smsMove(now, 7000000, tag: tag)],
      withdrawals: [
        Withdrawal(
            amount: 7000000,
            note: 'بانک ملت $tag',
            createdAt: '2026-11-24',
            status: 'completed'),
      ],
    );
    expect(tagged.smsOut, 7000000);
    expect(tagged.txOut, 0);
    expect(tagged.outflow, 7000000);

    final both = flow(
      sms: [smsMove(now, 5000000)],
      withdrawals: [
        Withdrawal(amount: 5000000, note: 'دستی', createdAt: '2026-11-24'),
      ],
    );
    expect(both.smsOut, 5000000);
    expect(both.txOut, 5000000);
    expect(both.outflow, 10000000);
  });

  test('pending and rejected withdrawals are excluded', () {
    final r = flow(withdrawals: [
      Withdrawal(amount: 1000, status: 'pending', createdAt: '2026-11-24'),
      Withdrawal(amount: 2000, status: 'rejected', createdAt: '2026-11-24'),
      Withdrawal(amount: 3000, status: 'completed', createdAt: '2026-11-24'),
    ]);
    expect(r.txOut, 3000);
  });

  test('bounced cheques are excluded; archived cleared still count', () {
    final bounced = flow(checks: [
      cheque(
        direction: checkDirectionPayable,
        amount: 9000,
        status: checkStatusBounced,
        payments: [
          CheckPayment(checkId: 1, amount: 1000, paidAt: '2026-11-24'),
        ],
      ),
    ]);
    expect(bounced.txOut, 0);
    expect(bounced.txIn, 0);

    final archived = flow(checks: [
      cheque(
        direction: checkDirectionReceivable,
        amount: 12000,
        status: checkStatusCleared,
        settled: '2026-11-24',
        archived: '2026-11-25',
      ),
    ]);
    expect(archived.txIn, 12000);
  });

  test('payments use paidAt; cancelled and unpaid pending do not count', () {
    final r = flow(period: CashflowPeriod.month, checks: [
      cheque(
        direction: checkDirectionReceivable,
        amount: 10000,
        status: checkStatusPending,
        payments: [
          CheckPayment(checkId: 1, amount: 4000, paidAt: '2026-11-24'),
          CheckPayment(checkId: 1, amount: 1500, paidAt: '2026-11-01'),
        ],
      ),
      cheque(
        direction: checkDirectionPayable,
        amount: 8000,
        status: checkStatusCancelled,
        settled: '2026-11-24',
      ),
      cheque(
        direction: checkDirectionPayable,
        amount: 5000,
        status: checkStatusPending,
      ),
    ]);
    expect(r.txIn, 4000); // 1500 is Aban, not Azar
    expect(r.txOut, 0);
  });

  test('PWO base and txs skipped on day, included on month and year', () {
    final pwo = PwoLedger(
      people: [PwoPerson(id: 'p1', name: 'A')],
      months: {
        pwoMonthKey(1405, 9): PwoMonth(
          year: 1405,
          month: 9,
          amounts: {'p1': 10000000},
          txs: [PwoTx(personId: 'p1', amount: 2000000)],
        ),
        pwoMonthKey(1405, 8): PwoMonth(
          year: 1405,
          month: 8,
          amounts: {'p1': 4000000},
        ),
      },
    );
    expect(flow(period: CashflowPeriod.day, pwo: pwo).txOut, 0);
    expect(flow(period: CashflowPeriod.month, pwo: pwo).txOut, 12000000);
    expect(flow(period: CashflowPeriod.year, pwo: pwo).txOut, 16000000);
  });

  test('tagged PWO tx is skipped when the SMS is present', () {
    const tag = '#deadbeef';
    final pwo = PwoLedger(
      people: [PwoPerson(id: 'p1', name: 'A')],
      months: {
        pwoMonthKey(1405, 9): PwoMonth(
          year: 1405,
          month: 9,
          amounts: const {},
          txs: [
            PwoTx(personId: 'p1', amount: 3000000, note: 'ملت $tag'),
          ],
        ),
      },
    );
    final r = flow(
      period: CashflowPeriod.month,
      sms: [smsMove(now, 3000000, tag: tag)],
      pwo: pwo,
    );
    expect(r.smsOut, 3000000);
    expect(r.txOut, 0);
  });

  test('smsUnavailable ignores SMS and still counts transactions', () {
    final r = flow(
      smsUnavailable: true,
      sms: [smsMove(now, 9000000, isIn: true)],
      withdrawals: [
        Withdrawal(amount: 1000, createdAt: '2026-11-24'),
      ],
    );
    expect(r.smsUnavailable, isTrue);
    expect(r.smsIn, 0);
    expect(r.smsOut, 0);
    expect(r.txOut, 1000);
    expect(r.inflow, 0);
    expect(r.outflow, 1000);
  });
}

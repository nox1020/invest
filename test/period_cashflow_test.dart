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

  test('SMS in and out are summed per period', () {
    final r = flow(sms: [
      smsMove(now, 5000000, isIn: true),
      smsMove(now, 3000000),
      smsMove(lastOfAban, 8000000), // last month: not today
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

  test(
      'bounced cheque: only payments made before it bounced count; archived cleared still count',
      () {
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
    expect(bounced.txOut, 1000);
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

  group('review fixes', () {
    test('UTC timestamps are converted to local before choosing the day', () {
      // nowIso() writes UTC without a zone; 21:30 UTC = 01:00 Tehran next day.
      final local = DateTime.utc(2026, 11, 23, 21, 30).toLocal();
      expect(cashflowDateOf('2026-11-23T21:30:00'), local);
      expect(cashflowDateOf('2026-11-23T21:30:00Z'), local);
      expect(cashflowDateOf('2026-11-24T01:00:00+03:30'), local);
      // Date-only and Jalali dates stay that local calendar day.
      expect(cashflowDateOf('2026-11-24'), DateTime(2026, 11, 24));
      expect(cashflowDateOf('1405/09/03'), DateTime(2026, 11, 24));

      final r = computePeriodCashflow(
        period: CashflowPeriod.day,
        now: local,
        sms: const [],
        withdrawals: [
          Withdrawal(amount: 1000, createdAt: '2026-11-23T21:30:00'),
        ],
        checks: const [],
        pwo: PwoLedger(people: [], months: {}),
      );
      expect(r.txOut, 1000);
    });

    test('cleared cheque with partial payments counts the remainder too', () {
      final r = flow(period: CashflowPeriod.month, checks: [
        cheque(
          direction: checkDirectionReceivable,
          amount: 10000,
          status: checkStatusCleared,
          settled: '2026-11-24',
          payments: [
            CheckPayment(checkId: 1, amount: 4000, paidAt: '2026-11-22'),
          ],
        ),
      ]);
      expect(r.txIn, 10000);
    });

    test('cancelled cheque: payments made before cancelling still count', () {
      final r = flow(checks: [
        cheque(
          direction: checkDirectionPayable,
          amount: 8000,
          status: checkStatusCancelled,
          payments: [
            CheckPayment(checkId: 1, amount: 2500, paidAt: '2026-11-24'),
          ],
        ),
      ]);
      expect(r.txOut, 2500);
    });

    test('only an exact SMS tag hides a row (no loose amount/day match)', () {
      // A tag-looking note whose SMS is not in the list: the row counts.
      final loose = flow(
        sms: [smsMove(now, 5000, tag: '#11112222')],
        withdrawals: [
          Withdrawal(
              amount: 5000, note: 'یادداشت #deadbeef', createdAt: '2026-11-24'),
        ],
      );
      expect(loose.txOut, 5000);
      // The exact tag hides the row even if the amount was edited.
      final exact = flow(
        sms: [smsMove(now, 5000, tag: '#11112222')],
        withdrawals: [
          Withdrawal(
              amount: 4800,
              note: 'بانک ملت #11112222',
              createdAt: '2026-11-24'),
        ],
      );
      expect(exact.txOut, 0);
      // A longer hex run is not that tag.
      final longer = flow(
        sms: [smsMove(now, 5000, tag: '#11112222')],
        withdrawals: [
          Withdrawal(
              amount: 5000, note: 'کد #11112222ab', createdAt: '2026-11-24'),
        ],
      );
      expect(longer.txOut, 5000);
    });

    test('likely duplicates: same direction & amount, ±1 day, untagged', () {
      final r = flow(
        period: CashflowPeriod.month,
        sms: [
          smsMove(now, 5000000),
          smsMove(now, 7000000, isIn: true),
          smsMove(now, 9000000),
          smsMove(now, 3000000, tag: '#aaaabbbb'),
        ],
        withdrawals: [
          // yesterday, same amount → pair
          Withdrawal(amount: 5000000, note: 'دستی', createdAt: '2026-11-23'),
          // 2 days earlier → no pair
          Withdrawal(amount: 9000000, createdAt: '2026-11-22'),
          // tagged → represented by its SMS, no pair
          Withdrawal(
              amount: 3000000, note: 'x #aaaabbbb', createdAt: '2026-11-24'),
          // same amount but opposite direction to the 7M deposit → no pair
          Withdrawal(amount: 7000000, createdAt: '2026-11-24'),
        ],
        checks: [
          cheque(
            direction: checkDirectionReceivable,
            amount: 7000000,
            status: checkStatusCleared,
            settled: '2026-11-25',
          ),
        ],
      );
      expect(r.duplicates, hasLength(2));
      expect(r.duplicates.where((d) => d.isIn), hasLength(1));
      expect(r.duplicates.where((d) => !d.isIn).single.toman, 5000000);
      // Both sides stay counted.
      expect(r.smsOut, 17000000);
      expect(r.txOut, 5000000 + 9000000 + 7000000);
    });

    test('day view: PWO without a day is flagged, not silently dropped', () {
      final pwo = PwoLedger(people: [], months: {
        pwoMonthKey(1405, 9):
            PwoMonth(year: 1405, month: 9, amounts: {'p0': 1000}),
      });
      final day = flow(pwo: pwo);
      expect(day.txOut, 0);
      expect(day.pwoMonthOnly, isTrue);
      final month = flow(period: CashflowPeriod.month, pwo: pwo);
      expect(month.txOut, 1000);
      expect(month.pwoMonthOnly, isFalse);
      final none = flow(pwo: PwoLedger(people: [], months: {}));
      expect(none.pwoMonthOnly, isFalse);
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:invest/domain/models/bank_check.dart';
import 'package:invest/domain/services/check_ledger.dart';

void main() {
  final today = DateTime(2026, 10, 17);

  BankCheck cheque({
    int? id,
    String direction = checkDirectionReceivable,
    double amount = 1000,
    String issue = '2026-10-01',
    String due = '2026-10-20',
    String number = '',
    String sayad = '',
    String bank = 'ملت',
    String status = checkStatusPending,
    String? settled,
  }) {
    return BankCheck(
      id: id,
      direction: direction,
      amount: amount,
      issueDate: issue,
      dueDate: due,
      checkNumber: number,
      sayadId: sayad,
      bankName: bank,
      status: status,
      settledDate: settled,
    );
  }

  test('splits receivables, debts, bounces, and due dates', () {
    final book = CheckLedger.summarize(
      [
        cheque(id: 1, amount: 2000000, due: '2026-10-20', number: '101'),
        cheque(
          id: 2,
          direction: checkDirectionPayable,
          amount: 500000,
          due: '2026-10-01',
          number: '202',
        ),
        cheque(
          id: 3,
          direction: checkDirectionPayable,
          amount: 200000,
          due: '2026-09-01',
          number: '203',
          status: checkStatusBounced,
        ),
        cheque(
          id: 4,
          amount: 400000,
          due: '2026-09-15',
          number: '104',
          status: checkStatusBounced,
        ),
        cheque(
          id: 5,
          amount: 900000,
          number: '105',
          status: checkStatusCleared,
          settled: '2026-10-10',
        ),
        cheque(
          id: 6,
          amount: 100000,
          number: '106',
          status: checkStatusEndorsed,
        ),
      ],
      today: today,
    );

    expect(book.openReceivable, 2000000);
    expect(book.openReceivableCount, 1);
    expect(book.debts, 700000);
    expect(book.debtCount, 2);
    expect(book.bouncedReceivable, 400000);
    expect(book.bouncedPayable, 200000);
    expect(book.net, 2000000 - 700000);
    expect(book.overdueCount, 3);
    expect(book.dueSoonCount, 1);
    expect(book.clearedReceivable, 900000);
    expect(book.nextDue?.id, 3);
  });

  test('due filter keeps overdue and the next week only', () {
    final rows = filterChecks(
      [
        cheque(id: 1, due: '2026-10-20', number: '1'),
        cheque(id: 2, due: '2026-12-01', number: '2'),
        cheque(
          id: 3,
          direction: checkDirectionPayable,
          due: '2026-10-10',
          number: '3',
        ),
      ],
      CheckListFilter.due,
      today: today,
    );
    expect(rows.map((e) => e.id), [3, 1]);
  });

  test('prepare accepts persian sayad digits and rejects contradictions', () {
    final saved = prepareBankCheck(
      cheque(
        amount: 1500000,
        number: '',
        sayad: '۱۲۳۴ ۵۶۷۸ ۹۰۱۲ ۳۴۵۶',
        bank: '  ملی  ',
      ),
    );
    expect(saved.sayadId, '1234567890123456');
    expect(saved.bankName, 'ملی');
    expect(saved.issueDate, '2026-10-01');

    expect(
      () => prepareBankCheck(cheque(due: '2026-09-01', number: '9')),
      throwsA(
        isA<ArgumentError>().having(
          (e) => e.message,
          'message',
          'سررسید نمی‌تواند قبل از تاریخ صدور باشد.',
        ),
      ),
    );
    expect(
      () => prepareBankCheck(cheque(number: '', sayad: '')),
      throwsA(isA<ArgumentError>()),
    );
    expect(
      () => prepareBankCheck(cheque(number: '1', sayad: '123')),
      throwsA(isA<ArgumentError>()),
    );
    expect(
      () => prepareBankCheck(
        cheque(
          direction: checkDirectionPayable,
          number: '1',
          status: checkStatusEndorsed,
        ),
      ),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('duplicate sayad or same bank number is rejected', () {
    final existing = prepareBankCheck(
      cheque(id: 7, number: '55', sayad: '1234567890123456', bank: 'ملت'),
    );
    expect(
      () => prepareBankCheck(
        cheque(id: 8, number: '99', sayad: '1234567890123456', bank: 'سپه'),
        others: [existing],
      ),
      throwsA(isA<ArgumentError>()),
    );
    expect(
      () => prepareBankCheck(
        cheque(id: 8, number: '55', bank: 'ملت'),
        others: [existing],
      ),
      throwsA(isA<ArgumentError>()),
    );
    final same = prepareBankCheck(
      cheque(id: 7, number: '55', sayad: '1234567890123456', bank: 'ملت'),
      others: [existing],
    );
    expect(same.id, 7);
  });

  test('round-trips storage map', () {
    final row = prepareBankCheck(
      cheque(
        id: 4,
        direction: checkDirectionPayable,
        amount: 250000,
        number: '88',
        status: checkStatusCleared,
        settled: '2026-10-11',
      ),
    );
    final again = BankCheck.fromMap(row.toMap());
    expect(again.direction, checkDirectionPayable);
    expect(again.amount, 250000);
    expect(again.status, checkStatusCleared);
    expect(again.settledDate, '2026-10-11');
    expect(again.statusLabel, 'پاس شده');
    expect(again.daysUntilDue(today), 3);
  });
}

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

  test('pending labels match the server and aliases survive the payload', () {
    final row = cheque(number: '1');
    expect(row.statusLabel, 'نزد صندوق');
    expect(row.pendingPlaceLabel, 'نزد صندوق');
    final payable = cheque(direction: checkDirectionPayable, number: '2');
    expect(payable.statusLabel, 'صادر شده');
    expect(payable.pendingPlaceLabel, 'صادر شده');

    final fromServer = BankCheck.fromMap({
      'id': 3,
      'direction': 'پرداختی',
      'amount': '1,500,000',
      'issue_date': '1403/01/01',
      'due_date': '1403-02-01',
      'status': 'برگشتی',
      'check_number': '77',
    });
    expect(fromServer.isPayable, isTrue);
    expect(fromServer.status, checkStatusBounced);
    expect(fromServer.statusLabel, 'برگشتی');
    expect(fromServer.amount, 1500000);
    expect(fromServer.issueDate, '2024-03-20');
    expect(fromServer.dueDate, isNotEmpty);

    final labeled = BankCheck.fromMap({
      'id': 9,
      'direction': 'receivable',
      'amount': 10,
      'issue_date': '2026-10-01',
      'due_date': '2026-10-20',
      'check_number': '9',
      'status': 'pending',
      'status_label': 'نزد صندوق',
      'due_label': 'سررسید فردا',
      'days_until_due': 1,
    });
    expect(labeled.statusLabel, 'نزد صندوق');
    expect(labeled.dueRelativeLabel(), 'سررسید فردا');
    expect(labeled.daysUntilDue(), 1);
  });

  test('cancelled sayad and number can be reused', () {
    final cancelled = cheque(
      id: 1,
      number: '1',
      sayad: '1234567890123456',
      status: checkStatusCancelled,
    );
    final reusedSayad = prepareBankCheck(
      cheque(id: 2, number: '2', sayad: '1234567890123456'),
      others: [cancelled],
    );
    expect(reusedSayad.sayadId, '1234567890123456');
    final reusedNumber = prepareBankCheck(
      cheque(id: 3, number: '1', bank: 'ملت'),
      others: [cancelled],
    );
    expect(reusedNumber.checkNumber, '1');
  });

  test('upload keeps local-only rows and patches pending edits', () {
    final local = [
      cheque(id: 1, number: '1', amount: 10),
      cheque(id: 2, number: '2', amount: 20),
    ];
    final remote = [
      cheque(id: 1, number: '1', amount: 10),
    ];
    final quiet = planCheckUpload(
      local: local,
      remote: remote,
      pushLocalEdits: false,
    );
    expect(quiet.toCreate.map((e) => e.id), [2]);
    expect(quiet.toUpdate, isEmpty);

    final edited = [
      cheque(id: 1, number: '1', amount: 99),
      cheque(id: 2, number: '2'),
    ];
    final pending = planCheckUpload(
      local: edited,
      remote: remote,
      pushLocalEdits: true,
    );
    expect(pending.toUpdate.single.amount, 99);
    final merged = mergeRemoteBook(
      local: edited,
      remote: [cheque(id: 1, number: '1', amount: 99)],
    );
    expect(merged.map((e) => e.id), [1, 2]);
  });

  test('reminder window is overdue through seven days', () {
    final rows = checksNeedingReminder(
      [
        cheque(id: 1, due: '2026-10-10', number: '1'),
        cheque(id: 2, due: '2026-10-24', number: '2'),
        cheque(id: 3, due: '2026-10-25', number: '3'),
        cheque(id: 4, due: '2026-10-20', number: '4', status: checkStatusCleared),
      ],
      today: today,
    );
    expect(rows.map((e) => e.id), [1, 2]);
  });

  test('search matches persian digits and در انتظار', () {
    final rows = filterChecks(
      [cheque(id: 1, number: '101')],
      CheckListFilter.pending,
      query: '۱۰۱',
      today: today,
    );
    expect(rows, hasLength(1));
  });
}

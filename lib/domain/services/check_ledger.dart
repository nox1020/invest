import 'package:invest/domain/models/bank_check.dart';
import 'package:invest/domain/models/check_payment.dart';

/// Which slice of the cheque book the list is showing.
enum CheckListFilter {
  all,
  receivable,
  payable,
  pending,
  due,
  bounced,
  overdue,
  partial,
  settled,
  check,
  deposit,
  archived
}

/// Open cheques that should raise a due reminder (overdue through 7 days).
const checkReminderWithinDays = 7;

/// Pending cheques that move portfolio value.
///
/// A pending receivable (دریافتی، نزد صندوق) is money still owed to us, so it
/// adds. A pending payable (پرداختی، صادرشده) is money we still owe, so it
/// subtracts. Cleared, endorsed, and cancelled cheques are finished. A bounce
/// stays in the cheque book as a claim, but it is not cash in the portfolio,
/// so it does not change NAV.
class ChequeNavEffect {
  const ChequeNavEffect({
    this.pendingReceivable = 0,
    this.pendingPayable = 0,
    this.pendingReceivableCount = 0,
    this.pendingPayableCount = 0,
  });

  final double pendingReceivable;
  final double pendingPayable;
  final int pendingReceivableCount;
  final int pendingPayableCount;

  static const zero = ChequeNavEffect();

  double get net => pendingReceivable - pendingPayable;

  bool get affectsNav =>
      pendingReceivable.abs() > 1e-9 || pendingPayable.abs() > 1e-9;

  static ChequeNavEffect of(Iterable<BankCheck> checks) {
    var receivable = 0.0;
    var payable = 0.0;
    var receivableCount = 0;
    var payableCount = 0;
    for (final check in checks) {
      if (check.status != checkStatusPending || check.isArchived) continue;
      if (check.isReceivable) {
        receivable += check.remainingAmount;
        receivableCount++;
      } else if (check.isPayable) {
        payable += check.remainingAmount;
        payableCount++;
      }
    }
    return ChequeNavEffect(
      pendingReceivable: receivable,
      pendingPayable: payable,
      pendingReceivableCount: receivableCount,
      pendingPayableCount: payableCount,
    );
  }
}

/// Totals for open cheques, debts, and due dates.
class CheckLedger {
  const CheckLedger({
    required this.openReceivable,
    required this.openReceivableCount,
    required this.debts,
    required this.debtCount,
    required this.bouncedReceivable,
    required this.bouncedReceivableCount,
    required this.bouncedPayable,
    required this.overdueAmount,
    required this.overdueCount,
    required this.dueSoonAmount,
    required this.dueSoonCount,
    required this.clearedReceivable,
    required this.clearedPayable,
    this.nextDue,
  });

  /// دریافتی‌های نزد صندوق (هنوز وصول نشده).
  final double openReceivable;
  final int openReceivableCount;

  /// بدهی: چک پرداختی صادرشده یا برگشتی.
  final double debts;
  final int debtCount;

  /// چک دریافتی برگشتی؛ هنوز مطالبه است ولی جزو دریافتی باز نیست.
  final double bouncedReceivable;
  final int bouncedReceivableCount;
  final double bouncedPayable;

  final double overdueAmount;
  final int overdueCount;

  /// Open cheques due today through the next 7 days.
  final double dueSoonAmount;
  final int dueSoonCount;

  final double clearedReceivable;
  final double clearedPayable;
  final BankCheck? nextDue;

  /// دریافتی باز منهای بدهی. مثبت یعنی خالص دریافتنی.
  double get net => openReceivable - debts;

  static const empty = CheckLedger(
    openReceivable: 0,
    openReceivableCount: 0,
    debts: 0,
    debtCount: 0,
    bouncedReceivable: 0,
    bouncedReceivableCount: 0,
    bouncedPayable: 0,
    overdueAmount: 0,
    overdueCount: 0,
    dueSoonAmount: 0,
    dueSoonCount: 0,
    clearedReceivable: 0,
    clearedPayable: 0,
  );

  static CheckLedger summarize(
    Iterable<BankCheck> checks, {
    DateTime? today,
  }) {
    final now = today ?? DateTime.now();
    var openReceivable = 0.0;
    var openReceivableCount = 0;
    var debts = 0.0;
    var debtCount = 0;
    var bouncedReceivable = 0.0;
    var bouncedReceivableCount = 0;
    var bouncedPayable = 0.0;
    var overdueAmount = 0.0;
    var overdueCount = 0;
    var dueSoonAmount = 0.0;
    var dueSoonCount = 0;
    var clearedReceivable = 0.0;
    var clearedPayable = 0.0;
    BankCheck? next;

    for (final c in checks) {
      if (c.isArchived) continue;
      if (c.countsAsReceivable) {
        openReceivable += c.remainingAmount;
        openReceivableCount++;
      }
      if (c.countsAsDebt) {
        debts += c.remainingAmount;
        debtCount++;
      }
      if (c.isReceivable && c.isBounced) {
        bouncedReceivable += c.remainingAmount;
        bouncedReceivableCount++;
      }
      if (c.isPayable && c.isBounced) {
        bouncedPayable += c.remainingAmount;
      }
      if (c.isReceivable && c.status == checkStatusCleared) {
        clearedReceivable += c.amount;
      }
      if (c.isPayable && c.status == checkStatusCleared) {
        clearedPayable += c.amount;
      }
      if (!c.isOpen) continue;
      final days = c.daysUntilDue(now);
      if (days < 0) {
        overdueAmount += c.remainingAmount;
        overdueCount++;
      } else if (days <= 7) {
        dueSoonAmount += c.remainingAmount;
        dueSoonCount++;
      }
      if (next == null || c.dueDate.compareTo(next.dueDate) < 0) {
        next = c;
      }
    }

    return CheckLedger(
      openReceivable: openReceivable,
      openReceivableCount: openReceivableCount,
      debts: debts,
      debtCount: debtCount,
      bouncedReceivable: bouncedReceivable,
      bouncedReceivableCount: bouncedReceivableCount,
      bouncedPayable: bouncedPayable,
      overdueAmount: overdueAmount,
      overdueCount: overdueCount,
      dueSoonAmount: dueSoonAmount,
      dueSoonCount: dueSoonCount,
      clearedReceivable: clearedReceivable,
      clearedPayable: clearedPayable,
      nextDue: next,
    );
  }
}

List<BankCheck> filterChecks(
  Iterable<BankCheck> checks,
  CheckListFilter filter, {
  String query = '',
  DateTime? today,
}) {
  final now = today ?? DateTime.now();
  final q = query.trim();
  final out = <BankCheck>[];
  for (final c in checks) {
    if (!_matchesFilter(c, filter, now)) continue;
    if (q.isNotEmpty && !_matchesQuery(c, q)) continue;
    out.add(c);
  }
  out.sort((a, b) {
    if (a.isOpen != b.isOpen) return a.isOpen ? -1 : 1;
    if (a.isOpen) return a.dueDate.compareTo(b.dueDate);
    final as = a.settledDate ?? a.dueDate;
    final bs = b.settledDate ?? b.dueDate;
    return bs.compareTo(as);
  });
  return out;
}

bool _matchesFilter(BankCheck c, CheckListFilter filter, DateTime today) {
  if (filter == CheckListFilter.archived) return c.isArchived;
  if (c.isArchived) return false;
  return switch (filter) {
    CheckListFilter.archived => false,
    CheckListFilter.all => true,
    CheckListFilter.receivable => c.isReceivable,
    CheckListFilter.payable => c.isPayable,
    CheckListFilter.pending => c.status == checkStatusPending,
    CheckListFilter.due => c.isOpen && c.daysUntilDue(today) <= 7,
    CheckListFilter.bounced => c.isBounced,
    CheckListFilter.overdue =>
      c.isActiveOpen && !c.isBounced && c.daysUntilDue(today) < 0,
    CheckListFilter.partial =>
      c.status == checkStatusPending && c.paymentState == paymentStatePartial,
    CheckListFilter.settled => c.isSettled,
    CheckListFilter.check => c.isCheck,
    CheckListFilter.deposit => c.isDeposit,
  };
}

bool _matchesQuery(BankCheck c, String query) {
  final hay = asciiDigits([
    c.checkNumber,
    c.sayadId,
    c.bankName,
    c.branch,
    c.counterparty,
    c.purpose,
    c.note,
    c.directionLabel,
    c.statusLabel,
    c.pendingPlaceLabel,
    c.kindLabel,
    c.paymentStateLabel,
  ].join(' '));
  return hay.contains(asciiDigits(query));
}

bool sameCheckIds(Iterable<BankCheck> a, Iterable<BankCheck> b) {
  final as = {for (final c in a) c.id};
  final bs = {for (final c in b) c.id};
  return as.length == bs.length && as.containsAll(bs);
}

/// Fields the server stores. Server labels and timestamps are ignored.
bool sameCheckContent(BankCheck a, BankCheck b) {
  return a.direction == b.direction &&
      (a.amount - b.amount).abs() < 0.001 &&
      a.issueDate == b.issueDate &&
      a.dueDate == b.dueDate &&
      a.checkNumber == b.checkNumber &&
      a.sayadId == b.sayadId &&
      a.bankName == b.bankName &&
      a.branch == b.branch &&
      a.counterparty == b.counterparty &&
      a.purpose == b.purpose &&
      a.note == b.note &&
      a.status == b.status &&
      (a.settledDate ?? '') == (b.settledDate ?? '') &&
      // Same rule for the «خرج شده» fields on a server that predates them.
      (!(a.endorseFromServer || b.endorseFromServer) ||
          (a.endorsedTo == b.endorsedTo && a.endorsedFor == b.endorsedFor)) &&
      // An older server never stores the flag; do not resend forever.
      (!(a.archiveFromServer || b.archiveFromServer) ||
          a.isArchived == b.isArchived) &&
      (!(a.kindFromServer || b.kindFromServer) || a.kind == b.kind) &&
      (!(a.paymentsFromServer || b.paymentsFromServer) ||
          samePaymentLists(a.payments, b.payments));
}

/// Local rows the device still has to send before it can trust the server book.
({List<BankCheck> toCreate, List<BankCheck> toUpdate}) planCheckUpload({
  required List<BankCheck> local,
  required List<BankCheck> remote,
  required bool pushLocalEdits,
  bool uploadMissingPayments = false,
  bool uploadMissingKind = false,
}) {
  final remoteById = <int, BankCheck>{
    for (final row in remote)
      if (row.id != null) row.id!: row,
  };
  final toCreate = <BankCheck>[];
  final toUpdate = <BankCheck>[];
  for (final row in local) {
    final id = row.id;
    if (id == null || !remoteById.containsKey(id)) {
      toCreate.add(row);
      continue;
    }
    final server = remoteById[id]!;
    final edited = pushLocalEdits && !sameCheckContent(row, server);
    final payments = uploadMissingPayments && localPaymentsAhead(row, server);
    final kind = uploadMissingKind && localKindAhead(row, server);
    if (edited || payments || kind) toUpdate.add(row);
  }
  return (toCreate: toCreate, toUpdate: toUpdate);
}

/// Local payment rows the server has not stored yet.
bool localPaymentsAhead(BankCheck local, BankCheck remote) {
  if (local.payments.isEmpty) return false;
  if (!remote.paymentsFromServer) return true;
  for (final payment in local.payments) {
    final stored = remote.payments.any(
      (row) =>
          (row.amount - payment.amount).abs() < 0.001 &&
          row.paidAt == payment.paidAt &&
          row.note == payment.note,
    );
    if (!stored) return true;
  }
  return false;
}

/// A deposit (or other non-default kind) the server has not stored yet.
bool localKindAhead(BankCheck local, BankCheck remote) {
  if (local.kind == checkKindCheck) return false;
  if (!remote.kindFromServer) return true;
  return local.kind != remote.kind;
}

/// Server rows win. Local rows the server does not have yet stay on the device.
List<BankCheck> mergeRemoteBook({
  required List<BankCheck> local,
  required List<BankCheck> remote,
}) {
  final remoteIds = {for (final row in remote) row.id};
  return [
    for (final row in remote) keepLocalArchive(row, local),
    for (final row in local)
      if (row.id == null || !remoteIds.contains(row.id)) row,
  ];
}

List<BankCheck> checksNeedingReminder(
  Iterable<BankCheck> checks, {
  DateTime? today,
}) {
  final now = today ?? DateTime.now();
  return [
    for (final c in checks)
      if (c.isActiveOpen &&
          c.id != null &&
          c.daysUntilDue(now) <= checkReminderWithinDays)
        c,
  ];
}

/// A server that does not know `archived_at` returns rows without it; keep
/// the flag from the device copy so archiving is never silently undone.
BankCheck keepLocalArchive(BankCheck remote, Iterable<BankCheck> local) {
  if (remote.archiveFromServer &&
      remote.endorseFromServer &&
      remote.kindFromServer &&
      remote.paymentsFromServer) {
    return remote;
  }
  for (final row in local) {
    if (row.id == remote.id) {
      var out = remote;
      if (!remote.archiveFromServer && row.isArchived) {
        out = out.copyWith(archivedAt: row.archivedAt);
      }
      // A server without the «خرج شده» fields must not erase them.
      if (!remote.endorseFromServer) {
        out = out.copyWith(
            endorsedTo: row.endorsedTo, endorsedFor: row.endorsedFor);
      }
      if (!remote.kindFromServer) {
        out = out.copyWith(kind: row.kind, kindFromServer: row.kindFromServer);
      }
      // A server that does not echo payments must not wipe local history.
      if (!remote.paymentsFromServer) {
        out = out.copyWith(
          payments: row.payments,
          paymentsFromServer: row.paymentsFromServer,
        );
      }
      return out;
    }
  }
  return remote;
}

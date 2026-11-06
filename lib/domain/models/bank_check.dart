import 'package:invest/domain/models/check_payment.dart';
import 'package:invest/domain/utils/dates.dart';
import 'package:invest/domain/utils/json_values.dart';

/// Cheque we will collect (دریافتی).
const checkDirectionReceivable = 'receivable';

/// Cheque we issued (پرداختی / بدهی).
const checkDirectionPayable = 'payable';

/// Still in the book: in hand, or issued and not yet passed.
const checkStatusPending = 'pending';

/// Collected (دریافتی) or passed (پرداختی).
const checkStatusCleared = 'cleared';

/// Returned by the bank (برگشتی).
const checkStatusBounced = 'bounced';

/// Endorsed / spent to someone else (خرج‌شده). Receivable only.
const checkStatusEndorsed = 'endorsed';

/// Voided (باطل).
const checkStatusCancelled = 'cancelled';

const checkStatuses = <String>[
  checkStatusPending,
  checkStatusCleared,
  checkStatusBounced,
  checkStatusEndorsed,
  checkStatusCancelled,
];

/// Paper or Sayad cheque (چک).
const checkKindCheck = 'check';

/// Security deposit (ودیعه).
const checkKindDeposit = 'deposit';

const checkKinds = <String>[checkKindCheck, checkKindDeposit];

const paymentStateUnpaid = 'unpaid';
const paymentStatePartial = 'partial';
const paymentStatePaid = 'paid';

/// One paper or Sayad cheque in the personal ledger.
class BankCheck {
  BankCheck({
    this.id,
    required this.direction,
    required this.amount,
    required this.issueDate,
    required this.dueDate,
    this.checkNumber = '',
    this.sayadId = '',
    this.bankName = '',
    this.branch = '',
    this.counterparty = '',
    this.purpose = '',
    this.note = '',
    this.endorsedTo = '',
    this.endorsedFor = '',
    this.endorseFromServer = false,
    this.status = checkStatusPending,
    this.settledDate,
    this.archivedAt,
    this.archiveFromServer = false,
    this.kind = checkKindCheck,
    this.kindFromServer = false,
    this.payments = const <CheckPayment>[],
    this.paymentsFromServer = false,
    this.createdAt = '',
    this.updatedAt = '',
    this.statusLabelFromServer,
    this.dueLabelFromServer,
    this.daysUntilDueFromServer,
  });

  int? id;
  String direction;
  double amount;

  /// Gregorian ISO `YYYY-MM-DD` (تاریخ صدور).
  String issueDate;

  /// Gregorian ISO `YYYY-MM-DD` (سررسید).
  String dueDate;
  String checkNumber;
  String sayadId;
  String bankName;
  String branch;

  /// Drawer for a receivable, payee for a payable.
  String counterparty;
  String purpose;
  String note;

  /// «خرج شده» receivable: who it was given to (به چه کسی).
  String endorsedTo;

  /// «خرج شده» receivable: what it paid for (بابت چه چیزی).
  String endorsedFor;

  /// True when the row came from a server that stores the two fields above.
  bool endorseFromServer;
  String status;
  String? settledDate;

  /// Set when the cheque was moved to «بایگانی». Data stays; an archived
  /// cheque is hidden from the main list and left out of totals and alerts.
  String? archivedAt;

  /// True when the row came from a server that knows `archived_at`. An older
  /// server drops the field, so the device copy keeps the flag instead.
  bool archiveFromServer;

  /// `check` or `deposit`. Existing rows default to cheque.
  String kind;

  /// True when the row came from a server that stores `kind`.
  bool kindFromServer;

  /// Local payment history. Lives in `check_payments`, not the checks row.
  List<CheckPayment> payments;

  /// True when the payload included a `payments` key.
  bool paymentsFromServer;
  String createdAt;
  String updatedAt;

  /// Read-only labels from `GET /checks`. Local text is used when absent.
  String? statusLabelFromServer;
  String? dueLabelFromServer;
  int? daysUntilDueFromServer;

  bool get isReceivable => direction == checkDirectionReceivable;
  bool get isPayable => direction == checkDirectionPayable;
  bool get isCheck => kind == checkKindCheck;
  bool get isDeposit => kind == checkKindDeposit;

  String get kindLabel => switch (kind) {
        checkKindDeposit => 'ودیعه',
        _ => 'چک',
      };

  double get recordedPaid =>
      payments.fold<double>(0, (sum, row) => sum + row.amount);

  /// Amount treated as paid for remaining-balance math.
  ///
  /// Historical cleared / endorsed / cancelled rows without payment history
  /// count as fully settled so old books keep a zero remaining balance.
  double get paidAmount {
    if (status == checkStatusCleared ||
        status == checkStatusEndorsed ||
        status == checkStatusCancelled) {
      return amount;
    }
    if (recordedPaid > amount) return amount;
    return recordedPaid < 0 ? 0 : recordedPaid;
  }

  /// What is still collectable or owed. Cancelled and endorsed items are
  /// closed. Bounced items keep their face value and cannot take payments.
  double get remainingAmount {
    if (status == checkStatusCancelled ||
        status == checkStatusEndorsed ||
        status == checkStatusCleared) {
      return 0;
    }
    if (status == checkStatusBounced) return amount;
    final left = amount - paidAmount;
    return left < 0 ? 0 : left;
  }

  String get paymentState {
    if (remainingAmount <= 0.001) return paymentStatePaid;
    if (paidAmount > 0.001) return paymentStatePartial;
    return paymentStateUnpaid;
  }

  String get paymentStateLabel => switch (paymentState) {
        paymentStatePaid => 'پرداخت‌شده',
        paymentStatePartial => 'پرداخت جزئی',
        _ => 'پرداخت‌نشده',
      };

  bool get canAcceptPayment {
    if (isArchived) return false;
    if (status == checkStatusCancelled ||
        status == checkStatusBounced ||
        status == checkStatusEndorsed) {
      return false;
    }
    return remainingAmount > 0.001;
  }

  String get paymentBlockReason {
    if (isArchived) return 'تراکنش بایگانی‌شده را نمی‌توان پرداخت کرد.';
    if (status == checkStatusCancelled) {
      return 'تراکنش باطل را نمی‌توان پرداخت کرد.';
    }
    if (status == checkStatusBounced) {
      return 'تراکنش برگشتی را نمی‌توان پرداخت کرد.';
    }
    if (status == checkStatusEndorsed) {
      return 'چک خرج‌شده را نمی‌توان پرداخت کرد.';
    }
    if (remainingAmount <= 0.001) {
      return 'مانده‌ای برای پرداخت نمانده است.';
    }
    return 'این تراکنش قابل پرداخت نیست.';
  }

  /// Still an open promise (نزد صندوق، صادرشده، یا برگشتی).
  bool get isOpen =>
      status == checkStatusPending || status == checkStatusBounced;

  /// Money we still expect to collect on a live receivable.
  bool get isArchived => (archivedAt ?? '').trim().isNotEmpty;

  /// Open and not archived: what alerts, due lists and totals look at.
  bool get isActiveOpen => isOpen && !isArchived;

  bool get countsAsReceivable =>
      !isArchived && isReceivable && status == checkStatusPending;

  /// Money we still owe: issued and not passed, including a bounce.
  bool get countsAsDebt =>
      !isArchived &&
      isPayable &&
      (status == checkStatusPending || status == checkStatusBounced);

  bool get isBounced => status == checkStatusBounced;

  bool get isSettled =>
      status == checkStatusCleared ||
      status == checkStatusEndorsed ||
      status == checkStatusCancelled;

  String get directionLabel => switch (direction) {
        checkDirectionReceivable => 'دریافتی',
        checkDirectionPayable => 'پرداختی',
        _ => 'نامشخص',
      };

  bool get isEndorsed => status == checkStatusEndorsed;

  /// «به فلانی · بابت فلان» for a spent cheque; empty when nothing was entered.
  String get endorseSummary {
    final to = endorsedTo.trim();
    final what = endorsedFor.trim();
    return [
      if (to.isNotEmpty) 'به $to',
      if (what.isNotEmpty) 'بابت $what',
    ].join(' · ');
  }

  String get counterpartyLabel => isReceivable ? 'صادرکننده' : 'در وجه';

  String get statusLabel {
    final fromServer = statusLabelFromServer?.trim() ?? '';
    if (fromServer.isNotEmpty) return fromServer;
    return labelForCheckStatus(status, receivable: isReceivable, kind: kind);
  }

  /// Where a pending cheque sits. Matches the server badge.
  String get pendingPlaceLabel => status == checkStatusPending
      ? (isReceivable ? 'نزد صندوق' : 'صادر شده')
      : '';

  /// Whole calendar days from [today] until [dueDate]. Negative means overdue.
  ///
  /// With no [today], a value returned by the server is kept so the device
  /// clock cannot disagree with Vinor.
  int daysUntilDue([DateTime? today]) {
    if (today == null && daysUntilDueFromServer != null) {
      return daysUntilDueFromServer!;
    }
    final due = _calendarDate(dueDate);
    final now = today ?? DateTime.now();
    final b = DateTime(now.year, now.month, now.day);
    return due.difference(b).inDays;
  }

  String dueRelativeLabel([DateTime? today]) {
    final fromServer = dueLabelFromServer?.trim() ?? '';
    if (today == null && fromServer.isNotEmpty) return fromServer;
    return dueRelativeText(daysUntilDue(today));
  }

  String get identityLabel {
    if (checkNumber.trim().isNotEmpty) return 'شماره ${checkNumber.trim()}';
    if (sayadId.trim().isNotEmpty) return 'صیاد ${sayadId.trim()}';
    if (isDeposit) return kindLabel;
    return 'بدون شماره';
  }

  BankCheck copyWith({
    int? id,
    String? direction,
    double? amount,
    String? issueDate,
    String? dueDate,
    String? checkNumber,
    String? sayadId,
    String? bankName,
    String? branch,
    String? counterparty,
    String? purpose,
    String? note,
    String? endorsedTo,
    String? endorsedFor,
    bool? endorseFromServer,
    String? status,
    String? settledDate,
    bool clearSettledDate = false,
    String? archivedAt,
    bool clearArchived = false,
    bool? archiveFromServer,
    String? kind,
    bool? kindFromServer,
    List<CheckPayment>? payments,
    bool? paymentsFromServer,
    String? createdAt,
    String? updatedAt,
    String? statusLabelFromServer,
    String? dueLabelFromServer,
    int? daysUntilDueFromServer,
  }) {
    final statusChanged = status != null && status != this.status;
    final dueChanged = dueDate != null && dueDate != this.dueDate;
    return BankCheck(
      id: id ?? this.id,
      direction: direction ?? this.direction,
      amount: amount ?? this.amount,
      issueDate: issueDate ?? this.issueDate,
      dueDate: dueDate ?? this.dueDate,
      checkNumber: checkNumber ?? this.checkNumber,
      sayadId: sayadId ?? this.sayadId,
      bankName: bankName ?? this.bankName,
      branch: branch ?? this.branch,
      counterparty: counterparty ?? this.counterparty,
      purpose: purpose ?? this.purpose,
      note: note ?? this.note,
      endorsedTo: endorsedTo ?? this.endorsedTo,
      endorsedFor: endorsedFor ?? this.endorsedFor,
      endorseFromServer: endorseFromServer ?? this.endorseFromServer,
      status: status ?? this.status,
      settledDate: clearSettledDate ? null : (settledDate ?? this.settledDate),
      archivedAt: clearArchived ? null : (archivedAt ?? this.archivedAt),
      archiveFromServer: archiveFromServer ?? this.archiveFromServer,
      kind: kind ?? this.kind,
      kindFromServer: kindFromServer ?? this.kindFromServer,
      payments: payments ?? this.payments,
      paymentsFromServer: paymentsFromServer ?? this.paymentsFromServer,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      statusLabelFromServer: statusChanged
          ? null
          : (statusLabelFromServer ?? this.statusLabelFromServer),
      dueLabelFromServer:
          dueChanged ? null : (dueLabelFromServer ?? this.dueLabelFromServer),
      daysUntilDueFromServer: dueChanged
          ? null
          : (daysUntilDueFromServer ?? this.daysUntilDueFromServer),
    );
  }

  factory BankCheck.fromMap(Map<String, Object?> m) {
    String text(Object? primary, Object? secondary) {
      final first = jsonText(primary);
      if (first.isNotEmpty) return first;
      return jsonText(secondary);
    }

    return BankCheck(
      id: jsonInt(m['id']),
      direction: _directionOf(m['direction']),
      amount: _amountOf(m['amount']),
      issueDate: _dateOf(m['issue_date'] ?? m['issueDate']),
      dueDate: _dateOf(m['due_date'] ?? m['dueDate']),
      checkNumber: text(m['check_number'], m['checkNumber']),
      sayadId: text(m['sayad_id'], m['sayadId']),
      bankName: text(m['bank_name'], m['bankName']),
      branch: jsonText(m['branch']),
      counterparty: jsonText(m['counterparty']),
      purpose: jsonText(m['purpose']),
      note: jsonText(m['note']),
      endorsedTo: text(m['endorsed_to'], m['endorsedTo']),
      endorsedFor: text(m['endorsed_for'], m['endorsedFor']),
      endorseFromServer: m.containsKey('endorsed_to'),
      status: _statusOf(m['status']),
      settledDate: _optionalDateOf(m['settled_date'] ?? m['settledDate']),
      archivedAt: _optionalText(m['archived_at'] ?? m['archivedAt']),
      archiveFromServer:
          m.containsKey('archived_at') || m.containsKey('is_archived'),
      kind: _kindOf(m['kind']),
      kindFromServer: m.containsKey('kind'),
      payments: _paymentsOf(m['payments']),
      paymentsFromServer: m.containsKey('payments'),
      createdAt: text(m['created_at'], m['createdAt']),
      updatedAt: text(m['updated_at'], m['updatedAt']),
      statusLabelFromServer: _optionalText(m['status_label']),
      dueLabelFromServer: _optionalText(m['due_label']),
      daysUntilDueFromServer: _optionalInt(m['days_until_due']),
    );
  }

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'direction': direction,
        'amount': amount,
        'issue_date': issueDate,
        'due_date': dueDate,
        'check_number': checkNumber,
        'sayad_id': sayadId,
        'bank_name': bankName,
        'branch': branch,
        'counterparty': counterparty,
        'purpose': purpose,
        'note': note,
        'endorsed_to': endorsedTo,
        'endorsed_for': endorsedFor,
        'status': status,
        'settled_date': settledDate,
        'archived_at': archivedAt,
        'kind': kind,
        'payments': payments.map((p) => p.toMap()).toList(),
        'created_at': createdAt,
        'updated_at': updatedAt,
      };

  /// SQLite `checks` row: no nested payment list.
  Map<String, Object?> toRow() {
    final row = Map<String, Object?>.from(toMap());
    row.remove('payments');
    return row;
  }
}

DateTime _calendarDate(String iso) {
  final s = iso.length >= 10 ? iso.substring(0, 10) : iso;
  final parts = s.split('-');
  if (parts.length != 3) return DateTime.now();
  final y = int.tryParse(parts[0]);
  final m = int.tryParse(parts[1]);
  final d = int.tryParse(parts[2]);
  if (y == null || m == null || d == null) return DateTime.now();
  return DateTime(y, m, d);
}

String dueRelativeText(int days) {
  if (days < 0) {
    final n = -days;
    return n == 1 ? 'دیروز سررسید شد' : '$n روز از سررسید گذشته';
  }
  if (days == 0) return 'سررسید امروز';
  if (days == 1) return 'سررسید فردا';
  return '$days روز تا سررسید';
}

String asciiDigits(String raw) {
  final buf = StringBuffer();
  for (final rune in raw.runes) {
    final ch = String.fromCharCode(rune);
    const persian = '۰۱۲۳۴۵۶۷۸۹';
    const arabic = '٠١٢٣٤٥٦٧٨٩';
    final pi = persian.indexOf(ch);
    if (pi >= 0) {
      buf.write(pi);
      continue;
    }
    final ai = arabic.indexOf(ch);
    if (ai >= 0) {
      buf.write(ai);
      continue;
    }
    buf.write(ch);
  }
  return buf.toString();
}

String normalizeSayadId(String raw) =>
    asciiDigits(raw).replaceAll(RegExp(r'\D'), '');

String _foldLabel(String raw) => raw.trim().replaceAll(RegExp(r'\s+'), ' ');

String labelForCheckStatus(
  String status, {
  required bool receivable,
  String kind = checkKindCheck,
}) {
  if (kind == checkKindDeposit) {
    return switch (status) {
      checkStatusPending => 'در انتظار',
      checkStatusCleared => 'تسویه شده',
      checkStatusCancelled => 'باطل',
      _ => status,
    };
  }
  return switch (status) {
    checkStatusPending => receivable ? 'نزد صندوق' : 'صادر شده',
    checkStatusCleared => receivable ? 'وصول شده' : 'پاس شده',
    checkStatusBounced => 'برگشتی',
    checkStatusEndorsed => 'خرج شده',
    checkStatusCancelled => 'باطل',
    _ => status,
  };
}

String _kindOf(Object? raw) {
  final t = '$raw'.trim();
  if (t.isEmpty) return checkKindCheck;
  if (t == checkKindDeposit || t == 'ودیعه' || t == 'deposit') {
    return checkKindDeposit;
  }
  if (t == checkKindCheck || t == 'چک' || t == 'cheque') {
    return checkKindCheck;
  }
  return checkKinds.contains(t) ? t : checkKindCheck;
}

List<CheckPayment> _paymentsOf(Object? raw) {
  if (raw is! List) return const <CheckPayment>[];
  return [
    for (final entry in raw)
      if (entry is Map) CheckPayment.fromMap(Map<String, Object?>.from(entry)),
  ];
}

String _directionOf(Object? raw) {
  final t = '$raw'.trim();
  if (t.isEmpty) return checkDirectionReceivable;
  if (t == checkDirectionPayable ||
      t == 'پرداختی' ||
      t == 'بدهی' ||
      t == 'issued' ||
      t == 'debt') {
    return checkDirectionPayable;
  }
  if (t == checkDirectionReceivable || t == 'دریافتی' || t == 'receive') {
    return checkDirectionReceivable;
  }
  return t;
}

String _statusOf(Object? raw) {
  final t = '$raw'.trim();
  if (t.isEmpty) return checkStatusPending;
  const aliases = <String, String>{
    checkStatusPending: checkStatusPending,
    'در انتظار': checkStatusPending,
    'نزد صندوق': checkStatusPending,
    'صادر شده': checkStatusPending,
    'issued': checkStatusPending,
    'waiting': checkStatusPending,
    checkStatusCleared: checkStatusCleared,
    'passed': checkStatusCleared,
    'paid': checkStatusCleared,
    'collected': checkStatusCleared,
    'پاس شده': checkStatusCleared,
    'پاس شد': checkStatusCleared,
    'وصول شده': checkStatusCleared,
    'وصول شد': checkStatusCleared,
    checkStatusBounced: checkStatusBounced,
    'returned': checkStatusBounced,
    'برگشتی': checkStatusBounced,
    'برگشت': checkStatusBounced,
    checkStatusEndorsed: checkStatusEndorsed,
    'خرج شده': checkStatusEndorsed,
    'خرج شد': checkStatusEndorsed,
    checkStatusCancelled: checkStatusCancelled,
    'canceled': checkStatusCancelled,
    'void': checkStatusCancelled,
    'باطل': checkStatusCancelled,
    'باطل شده': checkStatusCancelled,
  };
  return aliases[t] ??
      aliases[t.toLowerCase()] ??
      (checkStatuses.contains(t) ? t : checkStatusPending);
}

String _dateOf(Object? raw) => tryNormalizeToIso('$raw') ?? '';

String? _optionalText(Object? raw) {
  if (raw == null) return null;
  final text = '$raw'.trim();
  if (text.isEmpty || text == 'null') return null;
  return text;
}

int? _optionalInt(Object? raw) {
  if (raw is int) return raw;
  if (raw is num) return raw.toInt();
  return int.tryParse('$raw'.trim());
}

String? _optionalDateOf(Object? raw) {
  if (raw == null) return null;
  final text = '$raw'.trim();
  if (text.isEmpty || text == 'null') return null;
  return tryNormalizeToIso(text);
}

double _amountOf(Object? raw) {
  if (raw is num) return raw.toDouble();
  final parsed = double.tryParse(
    asciiDigits('$raw').trim().replaceAll(',', '').replaceAll('٬', ''),
  );
  return parsed ?? 0;
}

/// Clean fields and reject incomplete or contradictory cheques.
///
/// [others] are existing rows used to block a repeated Sayad id or the same
/// bank + number on another open document.
BankCheck prepareBankCheck(
  BankCheck draft, {
  Iterable<BankCheck> others = const [],
}) {
  final direction = draft.direction == checkDirectionPayable
      ? checkDirectionPayable
      : draft.direction == checkDirectionReceivable
          ? checkDirectionReceivable
          : '';
  if (direction.isEmpty) {
    throw ArgumentError('نوع را مشخص کنید: دریافتی یا پرداختی.');
  }

  final kind = _kindOf(draft.kind);
  final amountLabel = kind == checkKindDeposit ? 'ودیعه' : 'چک';

  final amount = draft.amount;
  if (amount.isNaN || amount.isInfinite || amount <= 0) {
    throw ArgumentError('مبلغ $amountLabel باید بزرگ‌تر از صفر باشد.');
  }
  if (amount > 1e16) {
    throw ArgumentError('مبلغ $amountLabel نامعتبر است.');
  }

  final issue = tryNormalizeToIso(draft.issueDate);
  final due = tryNormalizeToIso(draft.dueDate);
  if (issue == null) {
    throw ArgumentError('تاریخ صدور الزامی است.');
  }
  if (due == null) {
    throw ArgumentError('تاریخ سررسید الزامی است.');
  }
  if (parseIsoDate(due).isBefore(parseIsoDate(issue))) {
    throw ArgumentError('سررسید نمی‌تواند قبل از تاریخ صدور باشد.');
  }

  final number = _foldLabel(asciiDigits(draft.checkNumber));
  final sayad = normalizeSayadId(draft.sayadId);
  if (kind == checkKindCheck && number.isEmpty && sayad.isEmpty) {
    throw ArgumentError('شماره چک یا شناسه صیادی را وارد کنید.');
  }
  if (number.length > 32) {
    throw ArgumentError('شماره چک طولانی است.');
  }
  if (sayad.isNotEmpty && sayad.length != 16) {
    throw ArgumentError('شناسه صیادی باید ۱۶ رقم باشد.');
  }

  final bank = _clip(_foldLabel(draft.bankName), 48, 'نام بانک');
  final branch = _clip(_foldLabel(draft.branch), 48, 'شعبه');
  final party = _clip(_foldLabel(draft.counterparty), 80, 'طرف حساب');
  if (kind == checkKindDeposit && party.isEmpty) {
    throw ArgumentError('طرف حساب ودیعه را وارد کنید.');
  }
  final purpose = _clip(_foldLabel(draft.purpose), 120, 'بابت');
  final note = _clip(draft.note.trim(), 300, 'یادداشت');
  final endorsedTo = _clip(_foldLabel(draft.endorsedTo), 80, 'خرج شده به');
  final endorsedFor = _clip(_foldLabel(draft.endorsedFor), 120, 'بابت خرج');

  var status = draft.status.trim();
  if (!checkStatuses.contains(status)) status = checkStatusPending;
  if (kind == checkKindDeposit &&
      (status == checkStatusEndorsed || status == checkStatusBounced)) {
    throw ArgumentError('ودیعه را نمی‌توان برگشتی یا خرج‌شده ثبت کرد.');
  }
  if (direction == checkDirectionPayable && status == checkStatusEndorsed) {
    throw ArgumentError('چک پرداختی را نمی‌توان خرج‌شده ثبت کرد.');
  }

  final selfId = draft.id;
  for (final other in others) {
    if (other.id != null && other.id == selfId) continue;
    // Cancelled rows release both the Sayad id and the bank number.
    if (other.status == checkStatusCancelled) continue;
    if (sayad.isNotEmpty &&
        other.isCheck &&
        normalizeSayadId(other.sayadId) == sayad) {
      throw ArgumentError('این شناسه صیادی قبلاً ثبت شده است.');
    }
    if (kind == checkKindCheck &&
        number.isNotEmpty &&
        other.isCheck &&
        other.direction == direction &&
        _foldLabel(asciiDigits(other.checkNumber)) == number &&
        _foldLabel(other.bankName) == bank) {
      throw ArgumentError('چکی با همین شماره و بانک قبلاً ثبت شده است.');
    }
  }

  final String? settled = status == checkStatusPending
      ? null
      : (tryNormalizeToIso(draft.settledDate) ?? todayIso());

  return BankCheck(
    id: draft.id,
    direction: direction,
    amount: amount,
    issueDate: issue,
    dueDate: due,
    checkNumber: number,
    sayadId: sayad,
    bankName: bank,
    branch: branch,
    counterparty: party,
    purpose: purpose,
    note: note,
    endorsedTo: endorsedTo,
    endorsedFor: endorsedFor,
    endorseFromServer: draft.endorseFromServer,
    status: status,
    settledDate: settled,
    archivedAt: draft.archivedAt,
    archiveFromServer: draft.archiveFromServer,
    kind: kind,
    kindFromServer: draft.kindFromServer,
    payments: draft.payments,
    paymentsFromServer: draft.paymentsFromServer,
    createdAt: draft.createdAt,
    updatedAt: draft.updatedAt,
  );
}

String _clip(String value, int max, String label) {
  if (value.length <= max) return value;
  throw ArgumentError('$label طولانی است.');
}

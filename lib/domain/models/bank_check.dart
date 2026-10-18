import 'package:invest/domain/utils/dates.dart';

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
    this.status = checkStatusPending,
    this.settledDate,
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
  String status;
  String? settledDate;
  String createdAt;
  String updatedAt;

  /// Read-only labels from `GET /checks`. Local text is used when absent.
  String? statusLabelFromServer;
  String? dueLabelFromServer;
  int? daysUntilDueFromServer;

  bool get isReceivable => direction == checkDirectionReceivable;
  bool get isPayable => direction == checkDirectionPayable;

  /// Still an open promise (نزد صندوق، صادرشده، یا برگشتی).
  bool get isOpen =>
      status == checkStatusPending || status == checkStatusBounced;

  /// Money we still expect to collect on a live receivable.
  bool get countsAsReceivable =>
      isReceivable && status == checkStatusPending;

  /// Money we still owe: issued and not passed, including a bounce.
  bool get countsAsDebt =>
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

  String get counterpartyLabel => isReceivable ? 'صادرکننده' : 'در وجه';

  String get statusLabel {
    final fromServer = statusLabelFromServer?.trim() ?? '';
    if (fromServer.isNotEmpty) return fromServer;
    return labelForCheckStatus(status, receivable: isReceivable);
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
    String? status,
    String? settledDate,
    bool clearSettledDate = false,
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
      status: status ?? this.status,
      settledDate:
          clearSettledDate ? null : (settledDate ?? this.settledDate),
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      statusLabelFromServer: statusChanged
          ? null
          : (statusLabelFromServer ?? this.statusLabelFromServer),
      dueLabelFromServer: dueChanged
          ? null
          : (dueLabelFromServer ?? this.dueLabelFromServer),
      daysUntilDueFromServer: dueChanged
          ? null
          : (daysUntilDueFromServer ?? this.daysUntilDueFromServer),
    );
  }

  factory BankCheck.fromMap(Map<String, Object?> m) {
    final idVal = m['id'];
    final settled = (m['settled_date'] as String?) ??
        (m['settledDate'] as String?);
    return BankCheck(
      id: idVal is int ? idVal : (idVal as num?)?.toInt(),
      direction: _directionOf(m['direction']),
      amount: _amountOf(m['amount']),
      issueDate: _dateOf(m['issue_date'] ?? m['issueDate']),
      dueDate: _dateOf(m['due_date'] ?? m['dueDate']),
      checkNumber: (m['check_number'] as String?) ??
          (m['checkNumber'] as String?) ??
          '',
      sayadId: (m['sayad_id'] as String?) ?? (m['sayadId'] as String?) ?? '',
      bankName:
          (m['bank_name'] as String?) ?? (m['bankName'] as String?) ?? '',
      branch: (m['branch'] as String?) ?? '',
      counterparty: (m['counterparty'] as String?) ?? '',
      purpose: (m['purpose'] as String?) ?? '',
      note: (m['note'] as String?) ?? '',
      status: _statusOf(m['status']),
      settledDate: _optionalDateOf(settled),
      createdAt: (m['created_at'] as String?) ??
          (m['createdAt'] as String?) ??
          '',
      updatedAt: (m['updated_at'] as String?) ??
          (m['updatedAt'] as String?) ??
          '',
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
        'status': status,
        'settled_date': settledDate,
        'created_at': createdAt,
        'updated_at': updatedAt,
      };
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

String _foldLabel(String raw) =>
    raw.trim().replaceAll(RegExp(r'\s+'), ' ');

String labelForCheckStatus(String status, {required bool receivable}) {
  return switch (status) {
    checkStatusPending => receivable ? 'نزد صندوق' : 'صادر شده',
    checkStatusCleared => receivable ? 'وصول شده' : 'پاس شده',
    checkStatusBounced => 'برگشتی',
    checkStatusEndorsed => 'خرج شده',
    checkStatusCancelled => 'باطل',
    _ => status,
  };
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
    throw ArgumentError('نوع چک را مشخص کنید: دریافتی یا پرداختی.');
  }

  final amount = draft.amount;
  if (amount.isNaN || amount.isInfinite || amount <= 0) {
    throw ArgumentError('مبلغ چک باید بزرگ‌تر از صفر باشد.');
  }
  if (amount > 1e16) {
    throw ArgumentError('مبلغ چک نامعتبر است.');
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
  if (number.isEmpty && sayad.isEmpty) {
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
  final purpose = _clip(_foldLabel(draft.purpose), 120, 'بابت');
  final note = _clip(draft.note.trim(), 300, 'یادداشت');

  var status = draft.status.trim();
  if (!checkStatuses.contains(status)) status = checkStatusPending;
  if (direction == checkDirectionPayable && status == checkStatusEndorsed) {
    throw ArgumentError('چک پرداختی را نمی‌توان خرج‌شده ثبت کرد.');
  }

  final selfId = draft.id;
  for (final other in others) {
    if (other.id != null && other.id == selfId) continue;
    // Cancelled rows release both the Sayad id and the bank number.
    if (other.status == checkStatusCancelled) continue;
    if (sayad.isNotEmpty && normalizeSayadId(other.sayadId) == sayad) {
      throw ArgumentError('این شناسه صیادی قبلاً ثبت شده است.');
    }
    if (number.isNotEmpty &&
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
    status: status,
    settledDate: settled,
    createdAt: draft.createdAt,
    updatedAt: draft.updatedAt,
  );
}

String _clip(String value, int max, String label) {
  if (value.length <= max) return value;
  throw ArgumentError('$label طولانی است.');
}

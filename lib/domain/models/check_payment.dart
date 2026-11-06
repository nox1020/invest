import 'package:invest/domain/utils/dates.dart';
import 'package:invest/domain/utils/json_values.dart';

/// One recorded payment against a cheque or deposit.
class CheckPayment {
  CheckPayment({
    this.id,
    required this.checkId,
    required this.amount,
    required this.paidAt,
    this.note = '',
    this.createdAt = '',
  });

  int? id;
  int checkId;
  double amount;

  /// Gregorian ISO `YYYY-MM-DD` (or a full timestamp the UI can display).
  String paidAt;
  String note;
  String createdAt;

  CheckPayment copyWith({
    int? id,
    int? checkId,
    double? amount,
    String? paidAt,
    String? note,
    String? createdAt,
  }) {
    return CheckPayment(
      id: id ?? this.id,
      checkId: checkId ?? this.checkId,
      amount: amount ?? this.amount,
      paidAt: paidAt ?? this.paidAt,
      note: note ?? this.note,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  factory CheckPayment.fromMap(Map<String, Object?> m) {
    String text(Object? primary, Object? secondary) {
      final first = jsonText(primary);
      if (first.isNotEmpty) return first;
      return jsonText(secondary);
    }

    return CheckPayment(
      id: jsonInt(m['id']),
      checkId: jsonInt(m['check_id'] ?? m['checkId']) ?? 0,
      amount: _amountOf(m['amount']),
      paidAt: _dateOf(m['paid_at'] ?? m['paidAt']),
      note: jsonText(m['note']),
      createdAt: text(m['created_at'], m['createdAt']),
    );
  }

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'check_id': checkId,
        'amount': amount,
        'paid_at': paidAt,
        'note': note,
        'created_at': createdAt,
      };
}

String _dateOf(Object? raw) => tryNormalizeToIso('$raw') ?? '';

double _amountOf(Object? raw) {
  if (raw is num) return raw.toDouble();
  final digits =
      _asciiDigits('$raw').trim().replaceAll(',', '').replaceAll('٬', '');
  return double.tryParse(digits) ?? 0;
}

String _asciiDigits(String raw) {
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

bool samePaymentLists(Iterable<CheckPayment> a, Iterable<CheckPayment> b) {
  final left = a.toList();
  final right = b.toList();
  if (left.length != right.length) return false;
  for (var i = 0; i < left.length; i++) {
    if (left[i].checkId != right[i].checkId) return false;
    if ((left[i].amount - right[i].amount).abs() >= 0.001) return false;
    if ((left[i].paidAt) != (right[i].paidAt)) return false;
    if (left[i].note != right[i].note) return false;
  }
  return true;
}

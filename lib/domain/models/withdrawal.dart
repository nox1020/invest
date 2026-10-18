import 'package:invest/domain/utils/json_values.dart';

double computeWithdrawableAmount({
  required double realizedPnl,
  required double withdrawnTotal,
}) {
  final v = realizedPnl - withdrawnTotal;
  return v > 0 ? v : 0;
}

class Withdrawal {
  Withdrawal({
    this.id,
    required this.amount,
    this.note = '',
    this.status = 'completed',
    this.createdAt = '',
  });

  int? id;
  double amount;
  String note;
  String status;
  String createdAt;

  bool get isCompleted => status == 'completed';

  String get statusLabel => switch (status) {
        'pending' => 'در انتظار',
        'rejected' => 'رد شده',
        _ => 'انجام‌شده',
      };

  factory Withdrawal.fromMap(Map<String, Object?> m) {
    final created = jsonText(m['created_at']);
    return Withdrawal(
      id: jsonInt(m['id']),
      amount: jsonDouble(m['amount']) ?? 0,
      note: jsonText(m['note']),
      status: jsonText(m['status']).trim().isEmpty
          ? 'completed'
          : jsonText(m['status']),
      createdAt: created.isNotEmpty ? created : jsonText(m['createdAt']),
    );
  }

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'amount': amount,
        'note': note,
        'status': status,
        'created_at': createdAt,
      };
}

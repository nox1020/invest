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
    final idVal = m['id'];
    return Withdrawal(
      id: idVal is int ? idVal : (idVal as num?)?.toInt(),
      amount: (m['amount'] as num?)?.toDouble() ?? 0,
      note: (m['note'] as String?) ?? '',
      status: (m['status'] as String?) ?? 'completed',
      createdAt: (m['created_at'] as String?) ??
          (m['createdAt'] as String?) ??
          '',
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

import 'package:invest/domain/models/bank_check.dart';
import 'package:invest/domain/models/check_payment.dart';
import 'package:invest/domain/utils/dates.dart';

/// Validate a new payment. Rejects overpayment and closed statuses.
CheckPayment prepareCheckPayment({
  required BankCheck item,
  required double amount,
  String? paidAt,
  String note = '',
  int? id,
  String? createdAt,
}) {
  if (item.id == null) {
    throw ArgumentError('شناسه تراکنش نامعتبر است.');
  }
  if (!item.canAcceptPayment) {
    throw ArgumentError(item.paymentBlockReason);
  }
  if (amount.isNaN || amount.isInfinite || amount <= 0) {
    throw ArgumentError('مبلغ پرداخت باید بزرگ‌تر از صفر باشد.');
  }
  if (amount - item.remainingAmount > 0.001) {
    throw ArgumentError('مبلغ پرداخت از مانده بیشتر است.');
  }

  final when = tryNormalizeToIso(paidAt ?? '') ?? todayIso();
  final clipped = note.trim();
  if (clipped.length > 300) {
    throw ArgumentError('یادداشت طولانی است.');
  }
  final now = nowIso();
  return CheckPayment(
    id: id ?? DateTime.now().millisecondsSinceEpoch,
    checkId: item.id!,
    amount: amount,
    paidAt: when,
    note: clipped,
    createdAt: (createdAt ?? '').trim().isEmpty ? now : createdAt!,
  );
}

/// Append [payment] and clear the status when the remaining balance is gone.
BankCheck applyCheckPayment(BankCheck item, CheckPayment payment) {
  final nextPayments = [...item.payments, payment];
  final paid = nextPayments.fold<double>(0, (sum, row) => sum + row.amount);
  final remaining = item.amount - paid;
  if (remaining <= 0.001) {
    return item.copyWith(
      payments: nextPayments,
      status: checkStatusCleared,
      settledDate: payment.paidAt,
    );
  }
  return item.copyWith(payments: nextPayments);
}

/// Full settlement pays exactly the current remaining amount.
BankCheck settleCheckInFull(
  BankCheck item, {
  String? paidAt,
  String note = '',
}) {
  final payment = prepareCheckPayment(
    item: item,
    amount: item.remainingAmount,
    paidAt: paidAt,
    note: note,
  );
  return applyCheckPayment(item, payment);
}

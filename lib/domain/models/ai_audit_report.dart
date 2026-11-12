import 'package:invest/domain/services/check_ledger.dart';

/// Shared health bands for the card, the sheet, and the local rule engine.
const int aiScoreGood = 85;
const int aiScoreWatch = 60;

const String aiTargetOverdue = 'overdue';
const String aiTargetBounced = 'bounced';
const String aiTargetPartial = 'partial';
const String aiTargetDueSoon = 'due_soon';
const String aiTargetBankSms = 'bank_sms';

/// Cheque-book filter for an alert, when the alert opens the checks screen.
CheckListFilter? filterForAuditTarget(String target) {
  return switch (target) {
    aiTargetOverdue => CheckListFilter.overdue,
    aiTargetBounced => CheckListFilter.bounced,
    aiTargetPartial => CheckListFilter.partial,
    aiTargetDueSoon => CheckListFilter.due,
    _ => null,
  };
}

bool auditTargetOpensSms(String target) => target == aiTargetBankSms;

String aiHealthTitle(int score) {
  if (score >= aiScoreGood) return 'وضعیت حساب‌ها: مطلوب و پایدار';
  if (score >= aiScoreWatch) return 'وضعیت حساب‌ها: نیازمند توجه و پایش تعهدات';
  return 'وضعیت حساب‌ها: هشدار ریسک و کسری نقدینگی';
}

/// One cheque or deposit that still affects the audit.
class AiCheckFact {
  const AiCheckFact({
    required this.deposit,
    required this.payable,
    required this.remaining,
    required this.face,
    required this.days,
    required this.bounced,
    required this.pending,
    required this.partial,
    required this.counterparty,
    required this.dueIso,
    required this.thisWeek,
    required this.sameMonth,
    required this.within30,
    required this.within90,
  });

  final bool deposit;
  final bool payable;
  final double remaining;
  final double face;
  final int days;
  final bool bounced;
  final bool pending;
  final bool partial;
  final String counterparty;
  final String dueIso;
  final bool thisWeek;
  final bool sameMonth;
  final bool within30;
  final bool within90;

  bool get overdue => days < 0;
  bool get dueSoon => days >= 0 && days <= 7;
  bool get cheque => !deposit;

  Map<String, dynamic> toJson() => {
        'deposit': deposit,
        'payable': payable,
        'remaining': remaining,
        'face': face,
        'days': days,
        'bounced': bounced,
        'pending': pending,
        'partial': partial,
        'counterparty': counterparty,
        'due': dueIso,
        'week': thisWeek,
        'month': sameMonth,
        'd30': within30,
        'd90': within90,
      };

  factory AiCheckFact.fromJson(Map<String, dynamic> json) {
    return AiCheckFact(
      deposit: json['deposit'] == true,
      payable: json['payable'] == true,
      remaining: (json['remaining'] as num?)?.toDouble() ?? 0,
      face: (json['face'] as num?)?.toDouble() ?? 0,
      days: (json['days'] as num?)?.toInt() ?? 0,
      bounced: json['bounced'] == true,
      pending: json['pending'] == true,
      partial: json['partial'] == true,
      counterparty: json['counterparty']?.toString() ?? '',
      dueIso: json['due']?.toString() ?? '',
      thisWeek: json['week'] == true,
      sameMonth: json['month'] == true,
      within30: json['d30'] == true,
      within90: json['d90'] == true,
    );
  }
}

class CashflowBucket {
  const CashflowBucket({
    required this.id,
    required this.label,
    required this.payableCheques,
    required this.receivableCheques,
    required this.payableDeposits,
    required this.receivableDeposits,
  });

  final String id;
  final String label;
  final double payableCheques;
  final double receivableCheques;
  final double payableDeposits;
  final double receivableDeposits;

  double get payable => payableCheques + payableDeposits;
  double get receivable => receivableCheques + receivableDeposits;

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'payable_cheques': payableCheques,
        'receivable_cheques': receivableCheques,
        'payable_deposits': payableDeposits,
        'receivable_deposits': receivableDeposits,
      };

  factory CashflowBucket.fromJson(Map<String, dynamic> json) {
    return CashflowBucket(
      id: json['id']?.toString() ?? '',
      label: json['label']?.toString() ?? '',
      payableCheques: (json['payable_cheques'] as num?)?.toDouble() ?? 0,
      receivableCheques: (json['receivable_cheques'] as num?)?.toDouble() ?? 0,
      payableDeposits: (json['payable_deposits'] as num?)?.toDouble() ?? 0,
      receivableDeposits:
          (json['receivable_deposits'] as num?)?.toDouble() ?? 0,
    );
  }
}

class AiMonthlySummary {
  const AiMonthlySummary({
    required this.jalaliYear,
    required this.jalaliMonth,
    required this.label,
    required this.pwoLoaded,
    required this.pwoTotal,
    required this.pwoTarget,
    required this.withdrawalsTotal,
    required this.withdrawalCount,
    required this.openUnrealizedPnl,
    required this.openPricedTrades,
    required this.openUnpricedTrades,
    required this.monthRealizedPnl,
    required this.totalRealizedPnl,
    required this.monthClosedTrades,
    required this.doubleCountHits,
  });

  final int jalaliYear;
  final int jalaliMonth;
  final String label;
  final bool pwoLoaded;
  final double pwoTotal;
  final double pwoTarget;
  final double withdrawalsTotal;
  final int withdrawalCount;
  final double openUnrealizedPnl;
  final int openPricedTrades;
  final int openUnpricedTrades;
  final double monthRealizedPnl;
  final double totalRealizedPnl;
  final int monthClosedTrades;
  final int doubleCountHits;

  bool get pwoWithin => pwoTarget <= 0 || pwoTotal <= pwoTarget;

  Map<String, dynamic> toJson() => {
        'year': jalaliYear,
        'month': jalaliMonth,
        'label': label,
        'pwo_loaded': pwoLoaded,
        'pwo_total': pwoTotal,
        'pwo_target': pwoTarget,
        'withdrawals': withdrawalsTotal,
        'withdrawal_count': withdrawalCount,
        'open_unrealized': openUnrealizedPnl,
        'open_priced': openPricedTrades,
        'open_unpriced': openUnpricedTrades,
        'month_realized': monthRealizedPnl,
        'total_realized': totalRealizedPnl,
        'month_closed': monthClosedTrades,
        'double_counts': doubleCountHits,
      };

  factory AiMonthlySummary.fromJson(Map<String, dynamic> json) {
    return AiMonthlySummary(
      jalaliYear: (json['year'] as num?)?.toInt() ?? 0,
      jalaliMonth: (json['month'] as num?)?.toInt() ?? 0,
      label: json['label']?.toString() ?? '',
      pwoLoaded: json['pwo_loaded'] == true,
      pwoTotal: (json['pwo_total'] as num?)?.toDouble() ?? 0,
      pwoTarget: (json['pwo_target'] as num?)?.toDouble() ?? 0,
      withdrawalsTotal: (json['withdrawals'] as num?)?.toDouble() ?? 0,
      withdrawalCount: (json['withdrawal_count'] as num?)?.toInt() ?? 0,
      openUnrealizedPnl: (json['open_unrealized'] as num?)?.toDouble() ?? 0,
      openPricedTrades: (json['open_priced'] as num?)?.toInt() ?? 0,
      openUnpricedTrades: (json['open_unpriced'] as num?)?.toInt() ?? 0,
      monthRealizedPnl: (json['month_realized'] as num?)?.toDouble() ?? 0,
      totalRealizedPnl: (json['total_realized'] as num?)?.toDouble() ?? 0,
      monthClosedTrades: (json['month_closed'] as num?)?.toInt() ?? 0,
      doubleCountHits: (json['double_counts'] as num?)?.toInt() ?? 0,
    );
  }
}

/// On-device figures. Party names stay here and never go to Gemini.
class AiAuditSnapshot {
  const AiAuditSnapshot({
    required this.accountKey,
    required this.dayIso,
    required this.auditedAtIso,
    required this.auditedAtLabel,
    required this.totalCapitalToman,
    required this.cashKindToman,
    required this.kindValues,
    required this.chequePayable,
    required this.chequeReceivable,
    required this.depositPayable,
    required this.depositReceivable,
    required this.facts,
    required this.buckets,
    required this.monthly,
    required this.nearPayable,
    required this.nearReceivable,
    required this.cashWarning,
    required this.unhandledSms,
    required this.openTrades,
    required this.closedTrades,
    required this.inputHash,
  });

  final String accountKey;
  final String dayIso;
  final String auditedAtIso;
  final String auditedAtLabel;
  final double totalCapitalToman;

  /// Toman mark of assets labeled «نقد / تتر». Not rial cash in a bank.
  final double cashKindToman;
  final Map<String, double> kindValues;
  final double chequePayable;
  final double chequeReceivable;
  final double depositPayable;
  final double depositReceivable;
  final List<AiCheckFact> facts;
  final List<CashflowBucket> buckets;
  final AiMonthlySummary monthly;
  final double nearPayable;
  final double nearReceivable;
  final String? cashWarning;
  final int unhandledSms;
  final int openTrades;
  final int closedTrades;
  final String inputHash;

  Map<String, dynamic> toJson() => {
        'account': accountKey,
        'day': dayIso,
        'audited_at': auditedAtIso,
        'audited_label': auditedAtLabel,
        'capital': totalCapitalToman,
        'cash_kind': cashKindToman,
        'kinds': kindValues,
        'cheque_payable': chequePayable,
        'cheque_receivable': chequeReceivable,
        'deposit_payable': depositPayable,
        'deposit_receivable': depositReceivable,
        'facts': facts.map((f) => f.toJson()).toList(),
        'buckets': buckets.map((b) => b.toJson()).toList(),
        'monthly': monthly.toJson(),
        'near_payable': nearPayable,
        'near_receivable': nearReceivable,
        'cash_warning': cashWarning,
        'sms': unhandledSms,
        'open_trades': openTrades,
        'closed_trades': closedTrades,
        'hash': inputHash,
      };

  factory AiAuditSnapshot.fromJson(Map<String, dynamic> json) {
    final kindsRaw = json['kinds'];
    final kinds = <String, double>{};
    if (kindsRaw is Map) {
      kindsRaw.forEach((k, v) {
        if (v is num) kinds[k.toString()] = v.toDouble();
      });
    }
    return AiAuditSnapshot(
      accountKey: json['account']?.toString() ?? '',
      dayIso: json['day']?.toString() ?? '',
      auditedAtIso: json['audited_at']?.toString() ?? '',
      auditedAtLabel: json['audited_label']?.toString() ?? '',
      totalCapitalToman: (json['capital'] as num?)?.toDouble() ?? 0,
      cashKindToman: (json['cash_kind'] as num?)?.toDouble() ?? 0,
      kindValues: kinds,
      chequePayable: (json['cheque_payable'] as num?)?.toDouble() ?? 0,
      chequeReceivable: (json['cheque_receivable'] as num?)?.toDouble() ?? 0,
      depositPayable: (json['deposit_payable'] as num?)?.toDouble() ?? 0,
      depositReceivable: (json['deposit_receivable'] as num?)?.toDouble() ?? 0,
      facts: _mapList(json['facts'], AiCheckFact.fromJson),
      buckets: _mapList(json['buckets'], CashflowBucket.fromJson),
      monthly: AiMonthlySummary.fromJson(_asMap(json['monthly'])),
      nearPayable: (json['near_payable'] as num?)?.toDouble() ?? 0,
      nearReceivable: (json['near_receivable'] as num?)?.toDouble() ?? 0,
      cashWarning: json['cash_warning']?.toString(),
      unhandledSms: (json['sms'] as num?)?.toInt() ?? 0,
      openTrades: (json['open_trades'] as num?)?.toInt() ?? 0,
      closedTrades: (json['closed_trades'] as num?)?.toInt() ?? 0,
      inputHash: json['hash']?.toString() ?? '',
    );
  }
}

class AiAuditAlert {
  const AiAuditAlert({
    required this.severity,
    required this.title,
    required this.detail,
    required this.category,
    this.target = '',
  });

  final String severity;
  final String title;
  final String detail;
  final String category;
  final String target;

  bool get actionable =>
      target == aiTargetOverdue ||
      target == aiTargetBounced ||
      target == aiTargetPartial ||
      target == aiTargetDueSoon ||
      target == aiTargetBankSms;

  factory AiAuditAlert.fromJson(Map<String, dynamic> json) {
    return AiAuditAlert(
      severity: json['severity']?.toString() ?? 'medium',
      title: json['title']?.toString() ?? '',
      detail: json['detail']?.toString() ?? '',
      category: json['category']?.toString() ?? 'عمومی',
      target: json['target']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'severity': severity,
        'title': title,
        'detail': detail,
        'category': category,
        'target': target,
      };
}

class AiAuditReport {
  const AiAuditReport({
    required this.healthScore,
    required this.healthTitle,
    required this.summary,
    required this.alerts,
    required this.recommendations,
    required this.auditedAtIso,
    required this.snapshot,
    this.isAiGenerated = false,
    this.fallbackReason,
  });

  final int healthScore;
  final String healthTitle;
  final String summary;
  final List<AiAuditAlert> alerts;
  final List<String> recommendations;
  final String auditedAtIso;
  final AiAuditSnapshot snapshot;
  final bool isAiGenerated;

  /// Set when Gemini was attempted and the on-device report is shown instead.
  final String? fallbackReason;

  String get auditedAtLabel => snapshot.auditedAtLabel;
  double get totalCapitalToman => snapshot.totalCapitalToman;
  double get pendingChecksPayableToman => snapshot.chequePayable;
  double get pendingChecksReceivableToman => snapshot.chequeReceivable;
  double get pendingDepositsPayableToman => snapshot.depositPayable;
  double get pendingDepositsReceivableToman => snapshot.depositReceivable;
  int get overdueChecksCount =>
      snapshot.facts.where((f) => f.overdue && !f.bounced).length;
  int get openTradesCount => snapshot.openTrades;
  String get inputHash => snapshot.inputHash;
  String get accountKey => snapshot.accountKey;
  String get dayIso => snapshot.dayIso;

  AiAuditReport copyWithNarrative({
    int? healthScore,
    String? healthTitle,
    String? summary,
    List<String>? recommendations,
    bool? isAiGenerated,
    String? fallbackReason,
    bool clearFallback = false,
  }) {
    return AiAuditReport(
      healthScore: healthScore ?? this.healthScore,
      healthTitle: healthTitle ?? this.healthTitle,
      summary: summary ?? this.summary,
      alerts: alerts,
      recommendations: recommendations ?? this.recommendations,
      auditedAtIso: auditedAtIso,
      snapshot: snapshot,
      isAiGenerated: isAiGenerated ?? this.isAiGenerated,
      fallbackReason:
          clearFallback ? null : (fallbackReason ?? this.fallbackReason),
    );
  }

  factory AiAuditReport.fromJson(Map<String, dynamic> json) {
    final snapRaw = json['snapshot'];
    final snapshot = snapRaw is Map
        ? AiAuditSnapshot.fromJson(_asMap(snapRaw))
        : AiAuditSnapshot.fromJson(const <String, dynamic>{});
    return AiAuditReport(
      healthScore:
          ((json['health_score'] as num?)?.toInt() ?? 0).clamp(0, 100).toInt(),
      healthTitle: json['health_title']?.toString() ?? 'وضعیت پایدار',
      summary: json['summary']?.toString() ?? '',
      alerts: _mapList(json['alerts'], AiAuditAlert.fromJson),
      recommendations: [
        for (final item in (json['recommendations'] as List? ?? const []))
          item.toString(),
      ],
      auditedAtIso: json['audited_at']?.toString() ?? snapshot.auditedAtIso,
      snapshot: snapshot,
      isAiGenerated: json['is_ai'] == true,
      fallbackReason: json['fallback_reason']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'health_score': healthScore,
        'health_title': healthTitle,
        'summary': summary,
        'alerts': alerts.map((a) => a.toJson()).toList(),
        'recommendations': recommendations,
        'audited_at': auditedAtIso,
        'is_ai': isAiGenerated,
        'fallback_reason': fallbackReason,
        'snapshot': snapshot.toJson(),
        'total_capital': totalCapitalToman,
        'pending_payable': pendingChecksPayableToman,
        'pending_receivable': pendingChecksReceivableToman,
        'overdue_checks': overdueChecksCount,
        'open_trades': openTradesCount,
      };
}

class AiQaAnswer {
  const AiQaAnswer({
    required this.understood,
    required this.text,
    required this.redacted,
  });

  final bool understood;
  final String text;
  final String redacted;
}

class GeminiNarrative {
  const GeminiNarrative({
    required this.healthScore,
    required this.healthTitle,
    required this.summary,
    required this.recommendations,
  });

  final int healthScore;
  final String healthTitle;
  final String summary;
  final List<String> recommendations;
}

class CheckDigestItem {
  const CheckDigestItem({
    required this.title,
    required this.body,
    required this.id,
  });

  final String title;
  final String body;
  final int id;
}

class CheckDigestPlan {
  const CheckDigestPlan({
    required this.shouldSend,
    required this.fingerprint,
    required this.items,
  });

  final bool shouldSend;
  final String fingerprint;
  final List<CheckDigestItem> items;
}

Map<String, dynamic> _asMap(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return Map<String, dynamic>.from(value);
  return const {};
}

List<T> _mapList<T>(Object? raw, T Function(Map<String, dynamic>) parse) {
  if (raw is! List) return const [];
  final out = <T>[];
  for (final item in raw) {
    if (item is Map) out.add(parse(_asMap(item)));
  }
  return out;
}

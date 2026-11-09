import 'dart:convert';

/// یک مورد هشدار یا مغایرت شناسایی‌شده توسط حسابدار هوشمند
class AiAuditAlert {
  const AiAuditAlert({
    required this.severity, // 'high', 'medium', 'low'
    required this.title,
    required this.detail,
    required this.category, // 'چک', 'تراکنش', 'نقدینگی', 'ریسک', 'عمومی'
  });

  final String severity;
  final String title;
  final String detail;
  final String category;

  factory AiAuditAlert.fromJson(Map<String, dynamic> json) {
    return AiAuditAlert(
      severity: json['severity']?.toString() ?? 'medium',
      title: json['title']?.toString() ?? '',
      detail: json['detail']?.toString() ?? '',
      category: json['category']?.toString() ?? 'عمومی',
    );
  }

  Map<String, dynamic> toJson() => {
    'severity': severity,
    'title': title,
    'detail': detail,
    'category': category,
  };
}

/// گزارش جامع حسابرسی روزانه حساب‌ها توسط جمنای
class AiAuditReport {
  const AiAuditReport({
    required this.healthScore,
    required this.healthTitle,
    required this.summary,
    required this.alerts,
    required this.recommendations,
    required this.auditedAtIso,
    this.totalCapitalToman = 0,
    this.pendingChecksPayableToman = 0,
    this.pendingChecksReceivableToman = 0,
    this.overdueChecksCount = 0,
    this.openTradesCount = 0,
    this.isAiGenerated = true,
  });

  /// نمره سلامت حساب‌ها بین ۰ تا ۱۰۰
  final int healthScore;

  /// عنوان وضعیت (مثلاً «مطلوب»، «نیازمند توجه»، «بحرانی»)
  final String healthTitle;

  /// متن ارزیابی تحلیلی حسابدار
  final String summary;

  /// لیست هشدارهای حسابرسی
  final List<AiAuditAlert> alerts;

  /// توصیه‌های راهبردی حسابداری
  final List<String> recommendations;

  /// تاریخ و زمان انجام حسابرسی به فرمت ISO
  final String auditedAtIso;

  /// آمار کلیدی در زمان بازبینی
  final double totalCapitalToman;
  final double pendingChecksPayableToman;
  final double pendingChecksReceivableToman;
  final int overdueChecksCount;
  final int openTradesCount;

  /// آیا توسط مدل جمنای تولید شده یا موتور قوانین محلی
  final bool isAiGenerated;

  factory AiAuditReport.fromJson(Map<String, dynamic> json) {
    final rawAlerts = json['alerts'] as List? ?? [];
    final alertsList = rawAlerts
        .whereType<Map<String, dynamic>>()
        .map((e) => AiAuditAlert.fromJson(e))
        .toList();

    final rawRecs = json['recommendations'] as List? ?? [];
    final recsList = rawRecs.map((e) => e.toString()).toList();

    return AiAuditReport(
      healthScore: (json['health_score'] as num?)?.toInt() ?? 75,
      healthTitle: json['health_title']?.toString() ?? 'وضعیت پایدار',
      summary: json['summary']?.toString() ?? 'گزارش حسابرسی روزانه ثبت شد.',
      alerts: alertsList,
      recommendations: recsList,
      auditedAtIso: json['audited_at']?.toString() ?? DateTime.now().toIso8601String(),
      totalCapitalToman: (json['total_capital'] as num?)?.toDouble() ?? 0,
      pendingChecksPayableToman: (json['pending_payable'] as num?)?.toDouble() ?? 0,
      pendingChecksReceivableToman: (json['pending_receivable'] as num?)?.toDouble() ?? 0,
      overdueChecksCount: (json['overdue_checks'] as num?)?.toInt() ?? 0,
      openTradesCount: (json['open_trades'] as num?)?.toInt() ?? 0,
      isAiGenerated: json['is_ai'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() => {
    'health_score': healthScore,
    'health_title': healthTitle,
    'summary': summary,
    'alerts': alerts.map((a) => a.toJson()).toList(),
    'recommendations': recommendations,
    'audited_at': auditedAtIso,
    'total_capital': totalCapitalToman,
    'pending_payable': pendingChecksPayableToman,
    'pending_receivable': pendingChecksReceivableToman,
    'overdue_checks': overdueChecksCount,
    'open_trades': openTradesCount,
    'is_ai': isAiGenerated,
  };
}

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:invest/domain/models/ai_audit_report.dart';
import 'package:invest/domain/models/asset.dart';
import 'package:invest/domain/models/asset_kind.dart';
import 'package:invest/domain/models/bank_check.dart';
import 'package:invest/domain/models/trade.dart';
import 'package:invest/domain/models/withdrawal.dart';
import 'package:invest/domain/services/check_ledger.dart';
import 'package:invest/domain/services/double_count.dart';
import 'package:invest/domain/services/pwo_ledger.dart';
import 'package:invest/domain/utils/dates.dart';
import 'package:invest/domain/utils/money.dart';
import 'package:shamsi_date/shamsi_date.dart';

/// Figures the accountant reads. Tests build this without [AppState].
class AiAuditInput {
  const AiAuditInput({
    required this.now,
    required this.accountKey,
    this.totalCapitalToman = 0,
    this.assets = const [],
    this.checks = const [],
    this.openTrades = const [],
    this.closedTrades = const [],
    this.withdrawals = const [],
    this.pwo,
    this.unhandledSms = 0,
  });

  final DateTime now;
  final String accountKey;
  final double totalCapitalToman;
  final List<Asset> assets;
  final List<BankCheck> checks;
  final List<Trade> openTrades;
  final List<Trade> closedTrades;
  final List<Withdrawal> withdrawals;
  final PwoLedger? pwo;
  final int unhandledSms;
}

const aiQaSuggestions = <String>[
  'تا ۷ روز آینده چقدر باید بپردازم؟',
  'چه چک‌هایی سررسید گذشته‌اند؟',
  'مانده دریافتنی‌ها چقدر است؟',
  'ودیعه‌ها چقدر است؟',
  'PWO این ماه چقدر است؟',
];

const String geminiConsentExplainer =
    'حسابرسی پیش‌فرض روی خود دستگاه و با قواعد ثابت انجام می‌شود و چیزی ارسال نمی‌گردد. '
    'اگر رضایت بدهید و کلید جمنای را ذخیره کنید، فقط جمع‌های عددی فرستاده می‌شود: '
    'نوع دارایی و وزن هر نوع (بدون نام دارایی)، ماندهٔ چک و ودیعه به تفکیک، '
    'سود و زیان تجمیعی، نسبت PWO به هدف، و تعداد پیامک‌های تعیین‌تکلیف‌نشده. '
    'نام طرف حساب، شماره چک، شناسه صیاد و نام دارایی ارسال نمی‌شود.';

/// Calendar days until Friday. Iranian weeks end on Friday.
int daysUntilIranianWeekEnd(DateTime day) {
  final d = DateTime(day.year, day.month, day.day);
  return (DateTime.friday - d.weekday) % 7;
}

/// Server day-count wins. Otherwise calendar days, not a clock difference.
int auditDaysUntilDue(BankCheck check, DateTime today) {
  final server = check.daysUntilDueFromServer;
  if (server != null) return server;
  return check.daysUntilDue(today);
}

String persianDigits(String input) {
  const fa = '۰۱۲۳۴۵۶۷۸۹';
  final buffer = StringBuffer();
  for (var i = 0; i < input.length; i++) {
    final code = input.codeUnitAt(i);
    if (code >= 48 && code <= 57) {
      buffer.write(fa[code - 48]);
    } else if ((input[i] == ',' || input[i] == '.') &&
        i > 0 &&
        i + 1 < input.length &&
        _asciiDigit(input.codeUnitAt(i - 1)) &&
        _asciiDigit(input.codeUnitAt(i + 1))) {
      buffer.write(input[i] == ',' ? '٬' : '٫');
    } else {
      buffer.write(input[i]);
    }
  }
  return buffer.toString();
}

bool _asciiDigit(int code) => code >= 48 && code <= 57;

String tomanText(num value, {bool showSign = false}) {
  return persianDigits(
      formatMoney(value, forceToman: true, showSign: showSign));
}

String formatJalaliStamp(DateTime now) {
  final local = now.toLocal();
  final j = Jalali.fromDateTime(local);
  final hh = local.hour.toString().padLeft(2, '0');
  final mm = local.minute.toString().padLeft(2, '0');
  final raw = '${j.day} ${jalaliMonthNamesFa[j.month - 1]} ${j.year}، $hh:$mm';
  return persianDigits(raw);
}

String auditInputHash(Object canonical) {
  final raw = jsonEncode(canonical);
  return sha256.convert(utf8.encode(raw)).toString();
}

AiAuditSnapshot aggregateAudit(AiAuditInput input) {
  final today = DateTime(input.now.year, input.now.month, input.now.day);
  final weekLeft = daysUntilIranianWeekEnd(today);
  final nowJ = Jalali.fromDateTime(today);

  final kindValues = <String, double>{};
  for (final asset in input.assets) {
    final value = asset.totalValue;
    if (value <= 0) continue;
    final kind = detectAssetKind(
      name: asset.name,
      symbol: asset.symbol,
      notes: asset.notes,
    );
    kindValues[kind.id] = (kindValues[kind.id] ?? 0) + value;
  }
  final cashKind = kindValues[AssetKind.cash.id] ?? 0;

  final chequeBook = ChequeNavEffect.of(input.checks.where((c) => c.isCheck));
  final depositBook =
      ChequeNavEffect.of(input.checks.where((c) => c.isDeposit));

  final facts = <AiCheckFact>[];
  for (final check in input.checks) {
    final fact = _factOf(check, today, weekLeft, nowJ);
    if (fact != null) facts.add(fact);
  }

  final buckets = <CashflowBucket>[
    _bucket('overdue', 'سررسید گذشته', facts, (f) => f.overdue),
    _bucket('week', 'تا پایان این هفته', facts, (f) => f.thisWeek),
    _bucket('month', 'تا پایان این ماه', facts, (f) => f.sameMonth),
    _bucket('d30', '۳۰ روز آینده', facts, (f) => f.within30),
    _bucket('d90', '۹۰ روز آینده', facts, (f) => f.within90),
  ];

  final nearPayable = _sum(facts, (f) => f.payable && f.days <= 7);
  final nearReceivable = _sum(facts, (f) => !f.payable && f.days <= 7);
  final cashWarning = _cashWarning(
    nearPayable: nearPayable,
    nearReceivable: nearReceivable,
    cashKindToman: cashKind,
  );

  final monthly = _monthly(input, today, nowJ);
  final capital = input.totalCapitalToman > 0
      ? input.totalCapitalToman
      : kindValues.values.fold<double>(0, (a, b) => a + b);

  final fingerprint = <String, Object?>{
    'account': input.accountKey.trim(),
    'day': toIsoDate(today),
    'capital': capital,
    'kinds': kindValues,
    'cheques': [
      for (final fact in facts)
        {
          'd': fact.deposit,
          'p': fact.payable,
          'r': fact.remaining,
          'f': fact.face,
          'y': fact.days,
          'b': fact.bounced,
          's': fact.pending,
          't': fact.partial,
          'c': fact.counterparty,
          'u': fact.dueIso,
        },
    ],
    'pwo': monthly.pwoTotal,
    'pwo_target': monthly.pwoTarget,
    'pwo_loaded': monthly.pwoLoaded,
    'wd': monthly.withdrawalsTotal,
    'unreal': monthly.openUnrealizedPnl,
    'realized': monthly.monthRealizedPnl,
    'sms': input.unhandledSms,
    'double': monthly.doubleCountHits,
  };

  return AiAuditSnapshot(
    accountKey: input.accountKey.trim(),
    dayIso: toIsoDate(today),
    auditedAtIso: input.now.toIso8601String(),
    auditedAtLabel: formatJalaliStamp(input.now),
    totalCapitalToman: capital,
    cashKindToman: cashKind,
    kindValues: kindValues,
    chequePayable: chequeBook.pendingPayable,
    chequeReceivable: chequeBook.pendingReceivable,
    depositPayable: depositBook.pendingPayable,
    depositReceivable: depositBook.pendingReceivable,
    facts: facts,
    buckets: buckets,
    monthly: monthly,
    nearPayable: nearPayable,
    nearReceivable: nearReceivable,
    cashWarning: cashWarning,
    unhandledSms: input.unhandledSms,
    openTrades: input.openTrades.length,
    closedTrades: input.closedTrades.length,
    inputHash: auditInputHash(fingerprint),
  );
}

AiCheckFact? _factOf(
  BankCheck check,
  DateTime today,
  int weekLeft,
  Jalali nowJ,
) {
  if (check.isArchived || check.isSettled || !check.isActiveOpen) return null;
  final days = auditDaysUntilDue(check, today);
  final due = _dueIso(check);
  final sameMonth = due != null && _jalaliOfIso(due, nowJ);
  return AiCheckFact(
    deposit: check.isDeposit,
    payable: check.isPayable,
    remaining: check.remainingAmount,
    face: check.amount,
    days: days,
    bounced: check.isBounced,
    pending: check.status == checkStatusPending,
    partial: check.paymentState == paymentStatePartial,
    counterparty: check.counterparty.trim(),
    dueIso: due ?? '',
    thisWeek: days >= 0 && days <= weekLeft,
    sameMonth: sameMonth && days >= 0,
    within30: days >= 0 && days <= 30,
    within90: days >= 0 && days <= 90,
  );
}

String? _dueIso(BankCheck check) {
  final raw = check.dueDate.trim();
  if (raw.length < 10) return null;
  final slice = raw.substring(0, 10);
  if (DateTime.tryParse(slice) == null) return null;
  return slice;
}

bool _jalaliOfIso(String iso, Jalali now) {
  final parsed = DateTime.tryParse(iso);
  if (parsed == null) return false;
  final j = Jalali.fromDateTime(parsed);
  return j.year == now.year && j.month == now.month;
}

CashflowBucket _bucket(
  String id,
  String label,
  List<AiCheckFact> facts,
  bool Function(AiCheckFact fact) match,
) {
  return CashflowBucket(
    id: id,
    label: label,
    payableCheques: _sum(facts, (f) => match(f) && f.payable && f.cheque),
    receivableCheques: _sum(facts, (f) => match(f) && !f.payable && f.cheque),
    payableDeposits: _sum(facts, (f) => match(f) && f.payable && f.deposit),
    receivableDeposits: _sum(facts, (f) => match(f) && !f.payable && f.deposit),
  );
}

double _sum(List<AiCheckFact> facts, bool Function(AiCheckFact fact) match) {
  var total = 0.0;
  for (final fact in facts) {
    if (match(fact)) total += fact.remaining;
  }
  return total;
}

String? _cashWarning({
  required double nearPayable,
  required double nearReceivable,
  required double cashKindToman,
}) {
  if (nearPayable <= 0) return null;
  if (nearPayable <= nearReceivable + cashKindToman) return null;
  final pay = tomanText(nearPayable);
  final rec = tomanText(nearReceivable);
  final cash = tomanText(cashKindToman);
  final cashLine = cashKindToman > 0
      ? 'معادل تومانی گروه «نقد / تتر» در سبد $cash است. این گروه هم نقد و هم تتر یا ارز را در بر می‌گیرد و موجودی ریالی حساب بانکی نیست.'
      : 'گروه «نقد / تتر» در سبد خالی است؛ نقد ریالی قابل پرداخت از روی نوع دارایی شناسایی نشد.';
  return 'پرداختی‌های معوق تا ۷ روز آینده $pay است و از دریافتنی‌های همان بازه ($rec) بیشتر است. $cashLine قبل از سررسید، موجودی ریالی حساب را جدا بررسی کنید.';
}

AiMonthlySummary _monthly(AiAuditInput input, DateTime today, Jalali nowJ) {
  final ledger = input.pwo;
  final month = ledger?.months[pwoMonthKey(nowJ.year, nowJ.month)];
  final pwoTotal = month?.total ?? 0;
  final target = ledger?.target ?? 0;

  var withdrawals = 0.0;
  var withdrawalCount = 0;
  for (final row in input.withdrawals) {
    if (!row.isCompleted || row.amount <= 0) continue;
    if (!_stampInMonth(row.createdAt, nowJ)) continue;
    withdrawals += row.amount;
    withdrawalCount++;
  }

  var unrealized = 0.0;
  var priced = 0;
  var unpriced = 0;
  for (final trade in input.openTrades) {
    if (trade.currentPrice > 0) {
      unrealized += trade.unrealizedPnl;
      priced++;
    } else {
      unpriced++;
    }
  }

  var monthRealized = 0.0;
  var totalRealized = 0.0;
  var monthClosed = 0;
  for (final trade in input.closedTrades) {
    final pnl = trade.realizedPnl;
    if (pnl == null) continue;
    totalRealized += pnl;
    if (_stampInMonth(trade.sellDate, nowJ)) {
      monthRealized += pnl;
      monthClosed++;
    }
  }

  var doubles = 0;
  if (ledger != null) {
    for (final hit in findDoubleCounts(input.withdrawals, ledger)) {
      if (hit.year == nowJ.year && hit.month == nowJ.month) doubles++;
    }
  }

  return AiMonthlySummary(
    jalaliYear: nowJ.year,
    jalaliMonth: nowJ.month,
    label: '${jalaliMonthNamesFa[nowJ.month - 1]} ${nowJ.year}',
    pwoLoaded: ledger != null,
    pwoTotal: pwoTotal,
    pwoTarget: ledger == null ? 0 : target,
    withdrawalsTotal: withdrawals,
    withdrawalCount: withdrawalCount,
    openUnrealizedPnl: unrealized,
    openPricedTrades: priced,
    openUnpricedTrades: unpriced,
    monthRealizedPnl: monthRealized,
    totalRealizedPnl: totalRealized,
    monthClosedTrades: monthClosed,
    doubleCountHits: doubles,
  );
}

bool _stampInMonth(String? raw, Jalali now) {
  if (raw == null || raw.trim().isEmpty) return false;
  final parsed = DateTime.tryParse(raw.trim());
  if (parsed == null) return false;
  final local = parsed.isUtc ? parsed.toLocal() : parsed;
  final j = Jalali.fromDateTime(local);
  return j.year == now.year && j.month == now.month;
}

AiAuditReport buildLocalReport(AiAuditSnapshot snap) {
  final overdue = snap.facts.where((f) => f.overdue && !f.bounced).toList();
  final bounced = snap.facts.where((f) => f.bounced).toList();
  final dueSoon =
      snap.facts.where((f) => f.dueSoon && f.pending && !f.bounced).toList();
  final partial = snap.facts.where((f) => f.partial && f.pending).toList();
  final month = snap.monthly;

  var score = 95;
  final alerts = <AiAuditAlert>[];

  if (bounced.isNotEmpty) {
    score -= 30;
    final amount = bounced.fold<double>(0, (a, f) => a + f.remaining);
    alerts.add(AiAuditAlert(
      severity: 'high',
      title: '${bounced.length} فقره برگشتی',
      detail:
          'ماندهٔ مطالبه یا بدهی برگشتی ${tomanText(amount)} است. وضعیت وصول را در دفتر چک به‌روز کنید.',
      category: 'چک',
      target: aiTargetBounced,
    ));
  }
  if (overdue.isNotEmpty) {
    score -= 20;
    final amount = overdue.fold<double>(0, (a, f) => a + f.remaining);
    alerts.add(AiAuditAlert(
      severity: 'high',
      title: '${overdue.length} سند سررسید گذشته',
      detail:
          'جمع مانده ${tomanText(amount)} است و شامل چک و ودیعهٔ باز می‌شود.',
      category: 'چک',
      target: aiTargetOverdue,
    ));
  }
  if (dueSoon.isNotEmpty) {
    score -= 10;
    final amount = dueSoon.fold<double>(0, (a, f) => a + f.remaining);
    alerts.add(AiAuditAlert(
      severity: 'medium',
      title: '${dueSoon.length} سند تا ۷ روز آینده',
      detail:
          'جمع مانده ${tomanText(amount)} است. موجودی حساب را با این سررسیدها تطبیق دهید.',
      category: 'نقدینگی',
      target: aiTargetDueSoon,
    ));
  }
  if (partial.isNotEmpty) {
    score -= 5;
    alerts.add(AiAuditAlert(
      severity: 'medium',
      title: '${partial.length} سند با پرداخت جزئی',
      detail:
          'مانده پس از پرداخت‌های ثبت‌شده هنوز باز است و در جمع‌ها با مبلغ اسمی یکی نیست.',
      category: 'چک',
      target: aiTargetPartial,
    ));
  }
  if (snap.cashWarning != null) {
    score -= 10;
    alerts.add(AiAuditAlert(
      severity: 'medium',
      title: 'پرداختی نزدیک از ورودی قابل اتکا بیشتر است',
      detail: snap.cashWarning!,
      category: 'نقدینگی',
    ));
  }
  if (snap.unhandledSms > 0) {
    score -= 5;
    alerts.add(AiAuditAlert(
      severity: 'low',
      title: '${snap.unhandledSms} پیامک بانکی بدون تعیین تکلیف',
      detail: 'این پیامک‌ها هنوز به برداشت یا دفتر وصل نشده‌اند.',
      category: 'تراکنش',
      target: aiTargetBankSms,
    ));
  }
  if (month.pwoLoaded && month.pwoTarget > 0 && !month.pwoWithin) {
    score -= 5;
    alerts.add(AiAuditAlert(
      severity: 'medium',
      title: 'PWO ${month.label} بالاتر از هدف ماه',
      detail:
          'ثبت‌شده ${tomanText(month.pwoTotal)} و سقف ${tomanText(month.pwoTarget)} است.',
      category: 'برداشت',
    ));
  }
  if (month.doubleCountHits > 0) {
    score -= 5;
    alerts.add(AiAuditAlert(
      severity: 'low',
      title: '${month.doubleCountHits} مورد احتمال ثبت دوبارهٔ برداشت و PWO',
      detail:
          'مبلغ یک برداشت تکمیل‌شده با PWO همین ماه نزدیک است. هر پرداخت را فقط در یکی ثبت کنید.',
      category: 'برداشت',
    ));
  }

  score = score.clamp(20, 100).toInt();
  final recommendations = <String>[
    if (score >= aiScoreGood) ...[
      'انضباط اسناد در سطح مطلوب است.',
      'مازاد قابل برنامه‌ریزی را جدا از تعهدات سررسید نزدیک نگه دارید.',
    ] else ...[
      'اول اسناد سررسید گذشته و برگشتی را تعیین تکلیف کنید.',
      'قبل از تعهد تازه، ماندهٔ ۷ روز آینده را با ورودی همان بازه بسنجید.',
    ],
    'ارقام این گزارش از ماندهٔ پس از پرداخت جزئی است، نه مبلغ روی برگه.',
  ];

  final summary = StringBuffer()
    ..write(
        'بازبینی ${snap.auditedAtLabel} ارزش سبد را ${tomanText(snap.totalCapitalToman)} نشان می‌دهد. ')
    ..write(
        'چک پرداختی باز ${tomanText(snap.chequePayable)} و چک دریافتی باز ${tomanText(snap.chequeReceivable)} است. ')
    ..write(
        'ودیعهٔ پرداختی ${tomanText(snap.depositPayable)} و ودیعهٔ دریافتی ${tomanText(snap.depositReceivable)} جدا حساب شده است. ')
    ..write(
        'PWO ${month.label} ${month.pwoLoaded ? tomanText(month.pwoTotal) : 'هنوز بارگذاری نشده'}')
    ..write(month.pwoLoaded && month.pwoTarget > 0
        ? ' در برابر هدف ${tomanText(month.pwoTarget)}'
        : '')
    ..write(
        '. سود باز معاملات قیمت‌خورده ${tomanText(month.openUnrealizedPnl, showSign: true)}')
    ..write(
        ' و سود تحقق‌یافتهٔ همین ماه ${tomanText(month.monthRealizedPnl, showSign: true)} است.');

  return AiAuditReport(
    healthScore: score,
    healthTitle: aiHealthTitle(score),
    summary: summary.toString(),
    alerts: alerts,
    recommendations: recommendations,
    auditedAtIso: snap.auditedAtIso,
    snapshot: snap,
  );
}

/// Kinds, weights, and totals only. No names, parties, or cheque numbers.
Map<String, dynamic> redactedAuditPayload(AiAuditSnapshot snap) {
  final kindTotal = snap.kindValues.values.fold<double>(0, (a, b) => a + b);
  return {
    'date': snap.dayIso,
    'total_capital_toman': snap.totalCapitalToman,
    'asset_kinds': [
      for (final entry in snap.kindValues.entries)
        {
          'kind': entry.key,
          'label': _kindLabel(entry.key),
          'value_toman': entry.value,
          'weight': kindTotal <= 0 ? 0 : entry.value / kindTotal,
        },
    ],
    'cash_kind_toman': snap.cashKindToman,
    'cash_kind_note':
        'AssetKind.cash is labeled نقد / تتر and may be tether or FX, not rial bank cash.',
    'cheques': {
      'pending_payable_toman': snap.chequePayable,
      'pending_receivable_toman': snap.chequeReceivable,
    },
    'deposits': {
      'pending_payable_toman': snap.depositPayable,
      'pending_receivable_toman': snap.depositReceivable,
    },
    'forecast': [
      for (final bucket in snap.buckets)
        {
          'id': bucket.id,
          'payable_cheques': bucket.payableCheques,
          'receivable_cheques': bucket.receivableCheques,
          'payable_deposits': bucket.payableDeposits,
          'receivable_deposits': bucket.receivableDeposits,
        },
    ],
    'near_term': {
      'payable_toman': snap.nearPayable,
      'receivable_toman': snap.nearReceivable,
    },
    'counts': {
      'overdue': snap.facts.where((f) => f.overdue && !f.bounced).length,
      'bounced': snap.facts.where((f) => f.bounced).length,
      'due_soon': snap.facts.where((f) => f.dueSoon && !f.bounced).length,
      'partial': snap.facts.where((f) => f.partial).length,
      'unhandled_sms': snap.unhandledSms,
    },
    'monthly': {
      'label': snap.monthly.label,
      'pwo_loaded': snap.monthly.pwoLoaded,
      'pwo_total': snap.monthly.pwoTotal,
      'pwo_target': snap.monthly.pwoTarget,
      'withdrawals': snap.monthly.withdrawalsTotal,
      'open_unrealized': snap.monthly.openUnrealizedPnl,
      'open_priced_trades': snap.monthly.openPricedTrades,
      'open_unpriced_trades': snap.monthly.openUnpricedTrades,
      'month_realized': snap.monthly.monthRealizedPnl,
      'total_realized': snap.monthly.totalRealizedPnl,
      'double_count_hits': snap.monthly.doubleCountHits,
    },
    'trades': {
      'open_count': snap.openTrades,
      'closed_count': snap.closedTrades,
    },
  };
}

String _kindLabel(String id) {
  for (final kind in AssetKind.values) {
    if (kind.id == id) return kind.label;
  }
  return id;
}

GeminiNarrative? parseGeminiNarrative(String raw) {
  final extracted = extractJsonObject(stripCodeFences(raw));
  if (extracted == null) return null;
  Object? decoded;
  try {
    decoded = jsonDecode(extracted);
  } catch (_) {
    return null;
  }
  if (decoded is! Map) return null;
  final map = Map<String, dynamic>.from(decoded);
  final scoreRaw = map['health_score'];
  final title = map['health_title'];
  final summary = map['summary'];
  if (scoreRaw is! num || title is! String || summary is! String) return null;
  final score = scoreRaw.toInt();
  if (score < 0 || score > 100) return null;
  if (title.trim().isEmpty || summary.trim().isEmpty) return null;
  if (map.containsKey('alerts') && map['alerts'] is! List) return null;
  if (map.containsKey('recommendations') && map['recommendations'] is! List) {
    return null;
  }
  final recs = <String>[];
  final rawRecs = map['recommendations'];
  if (rawRecs is List) {
    for (final item in rawRecs) {
      if (item is! String || item.trim().isEmpty) return null;
      recs.add(item.trim());
    }
  }
  if (recs.isEmpty) return null;
  return GeminiNarrative(
    healthScore: score,
    healthTitle: title.trim(),
    summary: summary.trim(),
    recommendations: recs,
  );
}

String stripCodeFences(String raw) {
  var text = raw.trim();
  if (!text.startsWith('```')) return text;
  final newline = text.indexOf('\n');
  if (newline >= 0) text = text.substring(newline + 1);
  if (text.endsWith('```')) {
    text = text.substring(0, text.length - 3);
  }
  return text.trim();
}

String? extractJsonObject(String text) {
  final start = text.indexOf('{');
  if (start < 0) return null;
  var depth = 0;
  var inString = false;
  var escaped = false;
  for (var i = start; i < text.length; i++) {
    final char = text[i];
    if (inString) {
      if (escaped) {
        escaped = false;
        continue;
      }
      if (char == '\\') {
        escaped = true;
        continue;
      }
      if (char == '"') inString = false;
      continue;
    }
    if (char == '"') {
      inString = true;
      continue;
    }
    if (char == '{') depth++;
    if (char == '}') {
      depth--;
      if (depth == 0) return text.substring(start, i + 1);
    }
  }
  return null;
}

AiAuditReport applyGeminiNarrative(
    AiAuditReport local, GeminiNarrative narrative) {
  return local.copyWithNarrative(
    healthScore: narrative.healthScore,
    healthTitle: narrative.healthTitle,
    summary: narrative.summary,
    recommendations: narrative.recommendations,
    isAiGenerated: true,
    clearFallback: true,
  );
}

CheckDigestPlan planCheckDigest({
  required AiAuditSnapshot snap,
  required bool notificationsEnabled,
  required String? previousFingerprint,
}) {
  final overdue = snap.facts.where((f) => f.overdue && !f.bounced).toList();
  final soon =
      snap.facts.where((f) => f.dueSoon && f.pending && !f.bounced).toList();
  final overdueAmount = overdue.fold<double>(0, (a, f) => a + f.remaining);
  final soonAmount = soon.fold<double>(0, (a, f) => a + f.remaining);
  final fingerprint =
      '${snap.dayIso}|${overdue.length}|${overdueAmount.round()}|${soon.length}|${soonAmount.round()}';
  final items = <CheckDigestItem>[
    if (overdue.isNotEmpty)
      CheckDigestItem(
        id: 71001,
        title: 'چک و ودیعهٔ سررسید گذشته',
        body: '${overdue.length} سند، جمع مانده ${tomanText(overdueAmount)}',
      ),
    if (soon.isNotEmpty)
      CheckDigestItem(
        id: 71002,
        title: 'سررسید تا ۷ روز آینده',
        body: '${soon.length} سند، جمع مانده ${tomanText(soonAmount)}',
      ),
  ];
  final changed = fingerprint != previousFingerprint;
  return CheckDigestPlan(
    shouldSend: notificationsEnabled && changed && items.isNotEmpty,
    fingerprint: fingerprint,
    items: items,
  );
}

String normalizeQuestion(String raw) {
  var text = raw.trim().toLowerCase();
  text = text.replaceAll('\u200c', ' ').replaceAll('\u200d', '');
  text = text
      .replaceAll('ي', 'ی')
      .replaceAll('ك', 'ک')
      .replaceAll('ة', 'ه')
      .replaceAll('أ', 'ا')
      .replaceAll('إ', 'ا');
  text = _foldDigits(text);
  text = text.replaceAll(RegExp(r'\s+'), ' ');
  return text;
}

String _foldDigits(String raw) {
  const persian = '۰۱۲۳۴۵۶۷۸۹';
  const arabic = '٠١٢٣٤٥٦٧٨٩';
  final buffer = StringBuffer();
  for (final rune in raw.runes) {
    final char = String.fromCharCode(rune);
    final p = persian.indexOf(char);
    if (p >= 0) {
      buffer.write(p);
      continue;
    }
    final a = arabic.indexOf(char);
    if (a >= 0) {
      buffer.write(a);
      continue;
    }
    buffer.write(char);
  }
  return buffer.toString();
}

AiQaAnswer answerAccountantQuestion(String raw, AiAuditSnapshot snap) {
  final question = normalizeQuestion(raw);
  if (question.isEmpty) {
    return const AiQaAnswer(
      understood: false,
      text: 'پرسش را بنویسید یا یکی از پیشنهادها را بزنید.',
      redacted: 'پرسش خالی است.',
    );
  }
  if (_isPwo(question)) return _answerPwo(snap);
  if (question.contains('ودیعه')) return _answerDeposits(snap);
  if (_isOverdue(question)) return _answerOverdue(snap);
  if (_isReceivable(question)) return _answerReceivable(snap);
  if (_isPayable(question)) return _answerPayable(question, snap);
  return const AiQaAnswer(
    understood: false,
    text:
        'این پرسش را از روی دفاتر دستگاه جواب نمی‌دهم. یکی از پیشنهادها را بزنید: پرداخت تا چند روز آینده، سررسید گذشته، ماندهٔ دریافتنی، ودیعه، یا PWO این ماه.',
    redacted: 'پرسش خارج از پرسش‌های ثابت دستگاه است.',
  );
}

bool _isPwo(String question) {
  return question.contains('pwo') ||
      question.contains('پی دبلیو') ||
      question.contains('برداشت شخصی');
}

bool _isOverdue(String question) {
  return question.contains('سررسید گذشته') ||
      question.contains('سررسیدگذشته') ||
      question.contains('معوق') ||
      question.contains('عقب افتاد');
}

bool _isReceivable(String question) {
  return question.contains('دریافتن') ||
      question.contains('طلب') ||
      question.contains('وصول');
}

bool _isPayable(String question) {
  return question.contains('بپرداز') ||
      question.contains('پرداخت') ||
      question.contains('بدهی') ||
      question.contains('بدهکار') ||
      question.contains('باید بدم') ||
      question.contains('باید بدهم');
}

AiQaAnswer _answerPwo(AiAuditSnapshot snap) {
  final month = snap.monthly;
  if (!month.pwoLoaded) {
    const text = 'دفتر PWO هنوز بارگذاری نشده است.';
    return const AiQaAnswer(understood: true, text: text, redacted: text);
  }
  final total = tomanText(month.pwoTotal);
  final target = tomanText(month.pwoTarget);
  final stance =
      month.pwoWithin ? 'در سقف یا پایین‌تر از هدف' : 'بالاتر از هدف';
  final text =
      'PWO ${persianDigits(month.label)} برابر $total است. هدف ماه $target و وضعیت $stance است.';
  return AiQaAnswer(understood: true, text: text, redacted: text);
}

AiQaAnswer _answerDeposits(AiAuditSnapshot snap) {
  final text =
      'ودیعهٔ پرداختی باز ${tomanText(snap.depositPayable)} و ودیعهٔ دریافتی باز ${tomanText(snap.depositReceivable)} است. این مبالغ جدا از چک‌اند و مانده پس از پرداخت جزئی‌اند.';
  return AiQaAnswer(understood: true, text: text, redacted: text);
}

AiQaAnswer _answerReceivable(AiAuditSnapshot snap) {
  final total = snap.chequeReceivable + snap.depositReceivable;
  final text =
      'ماندهٔ دریافتنی باز ${tomanText(total)} است: چک ${tomanText(snap.chequeReceivable)} و ودیعه ${tomanText(snap.depositReceivable)}. برگشتی‌ها در این ماندهٔ نزد صندوق نیست.';
  return AiQaAnswer(understood: true, text: text, redacted: text);
}

AiQaAnswer _answerOverdue(AiAuditSnapshot snap) {
  final rows = snap.facts.where((f) => f.overdue && !f.bounced).toList();
  if (rows.isEmpty) {
    const text = 'سند بازِ سررسید گذشته‌ای در دفتر نیست.';
    return const AiQaAnswer(understood: true, text: text, redacted: text);
  }
  final amount = rows.fold<double>(0, (a, f) => a + f.remaining);
  final cheques = rows.where((f) => f.cheque).length;
  final deposits = rows.where((f) => f.deposit).length;
  final lines = <String>[
    '${rows.length} سند سررسید گذشته، جمع مانده ${tomanText(amount)} ($cheques چک، $deposits ودیعه).',
  ];
  for (final row in rows.take(8)) {
    final who = row.counterparty.isEmpty ? '' : ' · ${row.counterparty}';
    final kind = row.deposit ? 'ودیعه' : 'چک';
    final side = row.payable ? 'پرداختی' : 'دریافتی';
    lines.add(
      '$kind $side · ${tomanText(row.remaining)} · ${row.days.abs()} روز گذشته$who',
    );
  }
  final redacted = persianDigits(
    '${rows.length} سند سررسید گذشته، جمع مانده ${tomanText(amount)}؛ $cheques چک و $deposits ودیعه.',
  );
  return AiQaAnswer(
    understood: true,
    text: persianDigits(lines.join('\n')),
    redacted: redacted,
  );
}

AiQaAnswer _answerPayable(String question, AiAuditSnapshot snap) {
  final horizon = _horizonDays(question);
  final monthEnd =
      question.contains('این ماه') || question.contains('تا پایان ماه');
  final rows = snap.facts.where((fact) {
    if (!fact.payable || fact.bounced) return false;
    if (monthEnd) return fact.sameMonth;
    if (horizon == null) return fact.pending || fact.overdue;
    return fact.days >= 0 && fact.days <= horizon;
  }).toList();
  final amount = rows.fold<double>(0, (a, f) => a + f.remaining);
  final cheques =
      rows.where((f) => f.cheque).fold<double>(0, (a, f) => a + f.remaining);
  final deposits =
      rows.where((f) => f.deposit).fold<double>(0, (a, f) => a + f.remaining);
  final window = monthEnd
      ? 'تا پایان ${persianDigits(snap.monthly.label)}'
      : horizon == null
          ? 'در اسناد باز'
          : 'تا ${persianDigits('$horizon')} روز آینده (امروز تا همان روز)';
  final overdueLeft = horizon == null
      ? 0.0
      : snap.facts
          .where((f) => f.payable && f.overdue && !f.bounced)
          .fold<double>(0, (a, f) => a + f.remaining);
  final extra = overdueLeft > 0
      ? ' سررسید گذشته در این عدد نیست: ${tomanText(overdueLeft)}.'
      : '';
  final text =
      '$window باید ${tomanText(amount)} بپردازید: چک ${tomanText(cheques)} و ودیعه ${tomanText(deposits)}.$extra';
  return AiQaAnswer(understood: true, text: text, redacted: text);
}

int? _horizonDays(String question) {
  final match = RegExp(r'(\d+)\s*روز').firstMatch(question);
  if (match != null) return int.tryParse(match.group(1)!);
  if (question.contains('هفته')) return 7;
  return null;
}

import 'package:invest/data/bank_sms_store.dart';
import 'package:invest/data/biz_store.dart';
import 'package:invest/data/projects_store.dart';
import 'package:invest/domain/models/asset.dart';
import 'package:invest/domain/models/bank_check.dart';
import 'package:invest/domain/models/price_alert.dart';
import 'package:invest/domain/models/trade.dart';
import 'package:invest/domain/models/withdrawal.dart';
import 'package:invest/domain/services/holding_metrics.dart';
import 'package:invest/domain/services/pwo_ledger.dart';
import 'package:shamsi_date/shamsi_date.dart';

typedef Sheet = List<List<Object?>>;

/// Gregorian ISO (or DateTime) → Jalali `1405/08/03`; already-Jalali text
/// passes through.
String jDate(Object? v) {
  if (v == null) return '';
  DateTime? d;
  if (v is DateTime) {
    d = v.toLocal();
  } else {
    final s = '$v'.trim();
    if (s.isEmpty) return '';
    if (RegExp(r'^1[34]\d\d[/-]').hasMatch(s)) return s.replaceAll('-', '/');
    d = DateTime.tryParse(s)?.toLocal();
    if (d == null) return s;
  }
  final j = Jalali.fromDateTime(d);
  return '${j.year}/${j.month.toString().padLeft(2, '0')}/${j.day.toString().padLeft(2, '0')}';
}

String _projStatus(ProjectStatus s) => switch (s) {
      ProjectStatus.finished => 'تمام‌شده',
      ProjectStatus.active => 'در جریان',
      ProjectStatus.pipeline => 'در انتظار',
    };

/// Ads entries recorded from the dashboard shortcut live in the month note
/// as lines `تبلیغات <date>: <amount>[ — note]`.
final adsLine = RegExp(r'^تبلیغات (\S+): ([\d,]+)(?: — (.*))?$');

/// Everything the app holds, up to [now], as named sheets (Persian labels,
/// toman). Pure data; [BizAnnualReport] renders it to Excel / PDF.
Map<String, Sheet> buildFullExport({
  required DateTime now,
  required String yearKey,
  required List<({Asset asset, HoldingMetrics metrics})> holdings,
  required double holdingsValue,
  required double nav,
  required List<Trade> openTrades,
  required List<Trade> closedTrades,
  required double tradesRealized,
  required double yearTradesRealized,
  required BizSnapshot biz,
  required List<BizMonth> bizMonths,
  required List<Project> projects,
  required PwoLedger? pwo,
  required List<Withdrawal> withdrawals,
  required List<BankCheck> checks,
  required List<BankSmsDecision> smsHistory,
  required List<PriceAlert> priceAlerts,
  double? usdtTmn,
}) {
  final sold = biz.trades.where((t) => t.sold).toList();
  final propRealized = sold.fold<double>(0, (s, t) => s + (t.profit ?? 0));
  final propYear = sold
      .where((t) => t.sellDate.startsWith('$yearKey/'))
      .fold<double>(0, (s, t) => s + (t.profit ?? 0));
  final live = projects.where((p) => !p.archived).toList();
  final projRealized = live
      .where((p) => p.status == ProjectStatus.finished)
      .fold<double>(0, (s, p) => s + (p.profit ?? 0));
  final projExpected = live
      .where((p) => p.status == ProjectStatus.active)
      .fold<double>(0, (s, p) => s + (p.profit ?? 0));
  final unrealized = holdings.fold<double>(0, (s, h) => s + h.metrics.unrealizedPnl);
  final sysWithdrawn = withdrawals
      .where((w) => w.status != 'rejected')
      .fold<double>(0, (s, w) => s + w.amount);
  final pwoAll = pwo?.months.values.fold<double>(0, (s, m) => s + m.total) ?? 0;
  final pwoYear = pwo?.months.values
          .where((m) => '${m.year}' == yearKey)
          .fold<double>(0, (s, m) => s + m.total) ??
      0;
  double sumM(double Function(BizMonth) f) =>
      bizMonths.where((m) => '${m.year}' == yearKey).fold(0.0, (a, m) => a + f(m));

  final summary = <List<Object?>>[
    ['شرح', 'مبلغ (تومان)', 'توضیح'],
    ['تاریخ تهیه', jDate(now), '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')} — همهٔ داده‌ها تا این لحظه'],
    ['سال گزارش', yearKey, 'ستون‌های «امسال» از ابتدای سال تا امروز'],
    ['ارزش کل سبد (با چک‌ها)', nav, null],
    ['ارزش دارایی‌ها', holdingsValue, usdtTmn == null || usdtTmn <= 0 ? null : 'نرخ تتر ${usdtTmn.round()}'],
    ['سود باز (تحقق‌نیافته)', unrealized, null],
    ['سود تحقق‌یافته معاملات', tradesRealized, 'امسال: ${yearTradesRealized.round()}'],
    ['سود معاملات ملک (ملک و دفتر)', propRealized, 'امسال: ${propYear.round()}'],
    ['سود پروژه‌های تمام‌شده', projRealized, 'پیش‌بینی در جریان (حساب نشده): ${projExpected.round()}'],
    ['کل سود تحقق‌یافته', tradesRealized + propRealized + projRealized, 'معاملات + ملک + پروژه'],
    ['برداشت سیستم (کل)', sysWithdrawn, null],
    ['برداشت PWO (کل)', pwoAll, 'امسال: ${pwoYear.round()}'],
    ['درآمد دفتر امسال', sumM((m) => m.income), null],
    ['حقوق امسال', sumM((m) => m.staff), null],
    ['تبلیغات امسال', sumM((m) => m.ads), null],
    ['خالص ماهانه امسال', sumM((m) => m.net), null],
  ];

  final assets = <List<Object?>>[
    ['دارایی', 'نماد', 'مقدار', 'میانگین خرید', 'قیمت فعلی', 'بهای تمام‌شده', 'ارزش روز', 'سود/زیان', 'درصد', 'سهم از سبد٪'],
    for (final h in holdings)
      [
        h.asset.name, h.asset.symbol, h.metrics.quantity, h.metrics.avgBuyPrice,
        h.metrics.currentPrice, h.metrics.costBasis, h.metrics.marketValue,
        h.metrics.unrealizedPnl, double.parse(h.metrics.unrealizedPnlPct.toStringAsFixed(2)),
        holdingsValue > 0 ? double.parse((h.metrics.marketValue / holdingsValue * 100).toStringAsFixed(1)) : null,
      ],
    if (holdings.isNotEmpty)
      ['جمع', null, null, null, null,
        holdings.fold<double>(0, (s, h) => s + h.metrics.costBasis), holdingsValue, unrealized],
  ];

  final open = <List<Object?>>[
    ['دارایی', 'تاریخ خرید', 'مقدار', 'قیمت خرید', 'کارمزد', 'قیمت فعلی', 'ارزش روز', 'سود/زیان باز', 'یادداشت'],
    for (final t in openTrades)
      [t.assetName, jDate(t.buyDate), t.quantity, t.buyPrice, t.buyFee, t.currentPrice,
        t.quantity * t.currentPrice, t.quantity * t.currentPrice - t.buyCost, t.buyNote],
  ];

  final closed = <List<Object?>>[
    ['دارایی', 'تاریخ خرید', 'تاریخ فروش', 'مقدار', 'قیمت خرید', 'قیمت فروش', 'کارمزد', 'سود/زیان', 'درصد', 'روز'],
    for (final t in closedTrades)
      [t.assetName, jDate(t.buyDate), jDate(t.sellDate), t.quantity, t.buyPrice, t.sellPrice,
        t.buyFee + t.sellFee, t.realizedPnl, t.returnPct == null ? null : double.parse(t.returnPct!.toStringAsFixed(2)), t.holdingDays],
    if (closedTrades.isNotEmpty) ['جمع', null, null, null, null, null, null, tradesRealized],
  ];

  final allMonths = [...bizMonths]..sort((a, b) => a.year != b.year ? a.year.compareTo(b.year) : a.month.compareTo(b.month));
  final adsEntries = <List<Object?>>[
    ['سال', 'ماه', 'تاریخ', 'مبلغ', 'یادداشت'],
  ];
  for (final m in allMonths) {
    for (final line in m.note.split('\n')) {
      final x = adsLine.firstMatch(line.trim());
      if (x == null) continue;
      adsEntries.add([m.year, pwoMonthNames[m.month - 1], x[1], double.tryParse(x[2]!.replaceAll(',', '')), x[3] ?? '']);
    }
  }
  final monthsAll = <List<Object?>>[
    ['سال', 'ماه', 'درآمد', 'حقوق', 'PWO', 'تبلیغات', 'خالص', 'یادداشت'],
    for (final m in allMonths)
      if (!m.isEmpty) [m.year, pwoMonthNames[m.month - 1], m.income, m.staff, m.pwo, m.ads, m.net, m.note],
  ];

  final people = pwo?.people ?? const <PwoPerson>[];
  final pwoSheet = <List<Object?>>[
    ['سال', 'ماه', for (final p in people) p.name, 'جمع ماه', 'هدف ماهانه', 'وضعیت'],
    if (pwo != null)
      for (final m in (pwo.months.values.toList()..sort((a, b) => a.key.compareTo(b.key))))
        if (m.total > 0)
          [
            m.year, pwoMonthNames[m.month - 1],
            for (final p in people)
              (m.amounts[p.id] ?? 0) + m.txs.where((t) => t.personId == p.id).fold<double>(0, (s, t) => s + t.amount),
            m.total, pwo.target, m.withinTarget(pwo.target) ? 'در محدوده' : 'بالای هدف',
          ],
  ];
  final pwoTx = <List<Object?>>[
    ['سال', 'ماه', 'نفر', 'مبلغ', 'یادداشت'],
    if (pwo != null)
      for (final m in pwo.months.values)
        for (final t in m.txs)
          [m.year, pwoMonthNames[m.month - 1], pwo.personById(t.personId)?.name ?? t.personId, t.amount, t.note],
  ];

  final sys = <List<Object?>>[
    ['تاریخ', 'مبلغ', 'وضعیت', 'یادداشت'],
    for (final w in withdrawals) [jDate(w.createdAt), w.amount, w.status, w.note],
    if (withdrawals.isNotEmpty) ['جمع (بدون ردشده)', sysWithdrawn],
  ];

  final cheq = <List<Object?>>[
    ['نوع', 'مبلغ', 'تاریخ صدور', 'سررسید', 'وضعیت', 'طرف حساب', 'بانک', 'شماره', 'صیادی', 'بابت', 'تاریخ تسویه', 'بایگانی', 'یادداشت'],
    for (final c in checks)
      [c.directionLabel, c.amount, jDate(c.issueDate), jDate(c.dueDate), c.statusLabel, c.counterparty,
        c.bankName, c.checkNumber, c.sayadId, c.purpose, jDate(c.settledDate), c.isArchived ? 'بله' : '', c.note],
  ];

  final prop = <List<Object?>>[
    ['عنوان', 'تاریخ خرید', 'مبلغ خرید', 'تاریخ فروش', 'مبلغ فروش', 'متراژ', 'کد و نقشه', 'روز', 'سود/زیان', 'درصد', 'یادداشت'],
    for (final t in biz.trades)
      [t.title, t.buyDate, t.buyAmount, t.sellDate.isEmpty ? null : t.sellDate, t.sold ? t.sellAmount : null,
        t.area, t.extraCost, t.days, t.profit,
        t.profitPct == null ? null : double.parse(t.profitPct!.toStringAsFixed(2)), t.note],
    if (biz.trades.isNotEmpty) ['جمع سود فروخته‌شده', null, null, null, null, null, null, null, propRealized],
  ];

  final proj = <List<Object?>>[
    ['عنوان', 'نوع کار', 'شروع', 'پایان', 'قرارداد', 'هزینه', 'سود', 'درصد', 'وضعیت', 'بایگانی', 'یادداشت'],
    for (final p in projects)
      [p.title, p.workType, p.startDate, p.endDate, p.contract, p.cost, p.profit,
        p.profitPct == null ? null : double.parse(p.profitPct!.toStringAsFixed(2)),
        _projStatus(p.status), p.archived ? 'بله' : '', p.note],
  ];

  final sms = <List<Object?>>[
    ['تاریخ پیامک', 'بانک', 'مبلغ', 'تصمیم', 'ثبت در', 'زمان تصمیم'],
    for (final d in smsHistory)
      [jDate(d.at), d.bank, d.toman, d.saved ? 'ثبت شد' : 'رد شد',
        d.target == 'personal' ? 'شخصی (PWO)' : d.target == 'system' ? 'سیستم' : '', jDate(d.decidedAt)],
  ];

  final alerts = <List<Object?>>[
    ['نماد', 'نام', 'بالاتر از', 'پایین‌تر از', 'فعال'],
    for (final a in priceAlerts) [a.id, a.displayName, a.above, a.below, a.enabled ? 'بله' : 'خیر'],
  ];

  return {
    'خلاصه': summary,
    'دارایی‌ها': assets,
    'معاملات باز': open,
    'معاملات بسته': closed,
    'معاملات ملک': prop,
    'جدول ماهانه همه سال‌ها': monthsAll,
    'تبلیغات': adsEntries,
    'PWO ماهانه': pwoSheet,
    'PWO ردیف‌ها': pwoTx,
    'برداشت سیستم': sys,
    'چک‌ها': cheq,
    'پروژه‌ها': proj,
    'پیامک بانکی': sms,
    'هشدار قیمت': alerts,
  };
}

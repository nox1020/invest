import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invest/config/app_config.dart';
import 'package:invest/data/bank_sms_store.dart';
import 'package:invest/data/biz_store.dart';
import 'package:invest/data/projects_store.dart';
import 'package:invest/domain/models/asset.dart';
import 'package:invest/domain/models/bank_check.dart';
import 'package:invest/domain/models/price_alert.dart';
import 'package:invest/domain/models/trade.dart';
import 'package:invest/domain/models/withdrawal.dart';
import 'package:invest/domain/services/biz_annual_report.dart';
import 'package:invest/domain/services/full_export.dart';
import 'package:invest/domain/services/holding_metrics.dart';
import 'package:invest/domain/services/pwo_ledger.dart';

void main() {
  final biz = BizSnapshot({
    'year': 1405,
    'years': [1404, 1405],
    'trades': [
      {'id': 1, 'title': 'ملک الف', 'buy_date': '1404/02/01', 'sell_date': '1405/03/01', 'buy_amount': 1000, 'sell_amount': 1600, 'extra_cost': 0, 'profit': 600},
      {'id': 2, 'title': 'ملک ب', 'buy_date': '1405/04/01', 'sell_date': '', 'buy_amount': 900, 'sell_amount': 0, 'extra_cost': 0, 'profit': null},
    ],
    'months': [
      {'year': 1405, 'month': 8, 'staff': 30, 'pwo': 20, 'ads': 300, 'income': 1000, 'net': 650, 'has_ops': true, 'note': 'تبلیغات 1405/08/03: 300 — دیوار'},
    ],
  });
  final months = [
    BizMonth({'year': 1404, 'month': 12, 'staff': 10, 'pwo': 0, 'ads': 5, 'income': 100, 'net': 85, 'has_ops': true, 'note': ''}),
    ...biz.months,
  ];
  Map<String, Sheet> build() {
    final a = Asset(id: 1, name: 'طلا', symbol: 'GOLD', quantity: 2, avgBuyPrice: 100, currentPrice: 150);
    final open = Trade(assetId: 1, status: AppConfig.tradeOpen, quantity: 2, buyPrice: 100, buyDate: '2026-01-10', assetName: 'طلا', currentPrice: 150);
    final h = HoldingMetrics.activeHoldings(assets: [a], openTrades: [open]);
    final pwo = PwoLedger(target: 100)
      ..months[pwoMonthKey(1405, 8)] = PwoMonth(year: 1405, month: 8, amounts: {'p0': 40, 'p1': 70});
    return buildFullExport(
      now: DateTime(2026, 10, 25, 23, 0),
      yearKey: '1405',
      holdings: h,
      holdingsValue: 300,
      nav: 300,
      openTrades: [open],
      closedTrades: [
        Trade(assetId: 1, status: AppConfig.tradeClosed, quantity: 1, buyPrice: 100, sellPrice: 180, realizedPnl: 80, buyDate: '2026-01-01', sellDate: '2026-03-01', assetName: 'طلا'),
      ],
      tradesRealized: 80,
      yearTradesRealized: 80,
      biz: biz,
      bizMonths: months,
      projects: [
        Project({'id': 1, 'title': 'پ', 'status': 'finished', 'contract_amount': 90, 'cost': 40, 'profit': 50}),
        Project({'id': 2, 'title': 'ق', 'status': 'active', 'contract_amount': 90, 'cost': 10, 'profit': 80}),
      ],
      pwo: pwo,
      withdrawals: [
        Withdrawal(amount: 25, note: 'x', status: 'approved', createdAt: '2026-05-01'),
        Withdrawal(amount: 99, note: 'y', status: 'rejected', createdAt: '2026-05-02'),
      ],
      checks: [
        BankCheck(direction: checkDirectionPayable, amount: 60, issueDate: '2026-10-01', dueDate: '2026-10-30', status: checkStatusCleared),
        BankCheck(direction: checkDirectionReceivable, amount: 70, issueDate: '2026-10-01', dueDate: '2026-11-30'),
      ],
      smsHistory: [BankSmsDecision(bank: 'ملت', toman: 12, at: DateTime(2026, 10, 20), status: 'saved', target: 'personal', decidedAt: DateTime(2026, 10, 20))],
      priceAlerts: [PriceAlert(id: 'usdt', above: 90000)],
    );
  }

  Object? row(Sheet s, String label, [int col = 1]) => s.firstWhere((r) => r.first == label)[col];

  test('summary totals: every realized source, once; labelled to this moment', () {
    final x = build();
    final s = x['خلاصه']!;
    expect(row(s, 'تاریخ تهیه'), '1405/08/03');
    expect(row(s, 'سود تحقق‌یافته معاملات'), 80);
    expect(row(s, 'سود معاملات ملک (ملک و دفتر)'), 600);
    expect(row(s, 'سود پروژه‌های تمام‌شده'), 50);
    expect(row(s, 'کل سود تحقق‌یافته'), 730);
    expect(row(s, 'برداشت سیستم (کل)'), 25); // rejected excluded
    expect(row(s, 'برداشت PWO (کل)'), 110);
    expect(row(s, 'تبلیغات امسال'), 300); // only 1405
    expect(row(s, 'سود باز (تحقق‌نیافته)'), 100);
  });

  test('every module has its sheet with rows', () {
    final x = build();
    for (final k in ['دارایی‌ها', 'معاملات باز', 'معاملات بسته', 'معاملات ملک', 'جدول ماهانه همه سال‌ها',
      'تبلیغات', 'PWO ماهانه', 'برداشت سیستم', 'چک‌ها', 'پروژه‌ها', 'پیامک بانکی', 'هشدار قیمت']) {
      expect(x[k]!.length, greaterThan(1), reason: k);
    }
    expect(x['چک‌ها']!.length, 3); // all statuses
    expect(x['جدول ماهانه همه سال‌ها']!.length, 3); // both years
    expect(x['تبلیغات']![1], [1405, 'آبان', '1405/08/03', 300.0, 'دیوار']);
    final p = x['PWO ماهانه']!;
    expect(p[1].last, 'بالای هدف'); // 110 > 100
    expect(x['پروژه‌ها']!.length, 3);
  });

  test('xlsx and pdf include the comprehensive sheets', () async {
    final r = BizAnnualReport.from(biz, extra: build());
    expect(r.fileStem, 'گزارش-جامع-1405');
    final z = ZipDecoder().decodeBytes(r.toXlsx());
    final wb = utf8.decode(z.findFile('xl/workbook.xml')!.content as List<int>);
    for (final n in ['خلاصه', 'چک‌ها', 'پیامک بانکی', 'جدول ماهانه 1405', 'معاملات ملک سال 1405']) {
      expect(wb, contains(n));
    }
    ByteData f(String n) => ByteData.sublistView(File('assets/fonts/$n').readAsBytesSync());
    final pdf = await r.toPdf(font: f('Vazirmatn-Regular.ttf'), bold: f('Vazirmatn-Bold.ttf'));
    expect(pdf.length, greaterThan(1000));
  });
}

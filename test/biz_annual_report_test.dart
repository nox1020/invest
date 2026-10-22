import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invest/data/biz_store.dart';
import 'package:invest/domain/services/biz_annual_report.dart';

BizSnapshot _snap() => BizSnapshot({
      'year': 1405,
      'trades': [
        {'id': 1, 'buy_date': '1404/11/01', 'sell_date': '1405/02/10', 'buy_amount': 100.0,
          'sell_amount': 300.0, 'title': 'آپارتمان <A&B>', 'extra_cost': 5.0, 'note': '',
          'days': 99, 'profit': 200.0, 'profit_pct': 66.6667},
        {'id': 2, 'buy_date': '1405/03/01', 'sell_date': '', 'buy_amount': 50.0,
          'sell_amount': 0.0, 'title': 'زمین', 'extra_cost': 0.0, 'note': 'x',
          'days': null, 'profit': null, 'profit_pct': null},
        {'id': 3, 'buy_date': '1403/01/01', 'sell_date': '1404/01/01', 'buy_amount': 1.0,
          'sell_amount': 2.0, 'title': 'قدیمی', 'extra_cost': 0.0, 'note': '',
          'days': 365, 'profit': 1.0, 'profit_pct': 50.0},
      ],
      'months': [
        for (var m = 1; m <= 12; m++)
          {'year': 1405, 'month': m, 'staff': m == 2 ? 10.0 : 0.0, 'pwo': 0.0, 'ads': 0.0,
            'income': m == 2 ? 250.0 : 0.0, 'net': m == 2 ? 240.0 : 0.0, 'has_ops': m == 2},
      ],
    });

void main() {
  test('report keeps only trades touching the year; totals per month', () {
    final r = BizAnnualReport.from(_snap());
    expect(r.trades.map((t) => t.id), [1, 2]);
    expect(r.soldProfit, 200);
    expect(r.tradeProfitByMonth, {2: 200.0});
    expect(r.monthRows().last, ['جمع', 10.0, 0.0, 0.0, 250.0, 240.0, 200.0]);
  });

  test('xlsx is a valid zip with RTL sheets, escaped text and numbers', () {
    final bytes = BizAnnualReport.from(_snap()).toXlsx();
    final z = ZipDecoder().decodeBytes(bytes);
    final names = z.files.map((f) => f.name).toSet();
    expect(names, containsAll(['[Content_Types].xml', 'xl/workbook.xml',
      'xl/worksheets/sheet1.xml', 'xl/worksheets/sheet2.xml', 'xl/styles.xml']));
    final s1 = utf8.decode(z.findFile('xl/worksheets/sheet1.xml')!.content as List<int>);
    expect(s1, contains('rightToLeft="1"'));
    expect(s1, contains('آپارتمان &lt;A&amp;B&gt;'));
    expect(s1, contains('<v>300</v>'));
    expect(s1, isNot(contains('قدیمی')));
    final wb = utf8.decode(z.findFile('xl/workbook.xml')!.content as List<int>);
    expect(wb, contains('جدول ماهانه'));
  });

  test('pdf renders with the bundled Persian font', () async {
    ByteData f(String n) => ByteData.sublistView(File('assets/fonts/$n').readAsBytesSync());
    final pdf = await BizAnnualReport.from(_snap())
        .toPdf(font: f('Vazirmatn-Regular.ttf'), bold: f('Vazirmatn-Bold.ttf'));
    expect(String.fromCharCodes(pdf.sublist(0, 5)), '%PDF-');
    expect(pdf.length, greaterThan(2000));
    final out = Platform.environment['BIZ_PDF_OUT'];
    if (out != null) File(out).writeAsBytesSync(pdf);
  });
}

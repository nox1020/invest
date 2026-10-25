import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:invest/data/biz_store.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

const _monthNames = [
  'فروردین', 'اردیبهشت', 'خرداد', 'تیر', 'مرداد', 'شهریور',
  'مهر', 'آبان', 'آذر', 'دی', 'بهمن', 'اسفند',
];

/// One year of «ملک و دفتر»: trades bought or sold in the year plus the
/// monthly table. Pure data → Excel (xlsx) / PDF bytes. Read-only.
class BizAnnualReport {
  BizAnnualReport._(this.year, this.trades, this.months, this.tradeProfitByMonth, this.extra);

  /// Comprehensive sheets (summary, assets, trades, PWO, cheques, …) placed
  /// before the property/month sheets. Empty = the classic biz-only report.
  final Map<String, List<List<Object?>>> extra;
  bool get full => extra.isNotEmpty;

  final int year;
  final List<PropertyTrade> trades;
  final List<BizMonth> months;
  final Map<int, double> tradeProfitByMonth;

  static BizAnnualReport from(BizSnapshot s,
      {int? year, Map<String, List<List<Object?>>> extra = const {}}) {
    final y = year ?? s.year ?? 0;
    bool inYear(String d) => d.startsWith('$y/');
    final ts = [
      for (final t in s.trades)
        if (inYear(t.buyDate) || inYear(t.sellDate)) t
    ];
    final tp = <int, double>{};
    for (final t in s.trades) {
      if (!t.sold || !inYear(t.sellDate)) continue;
      final m = int.tryParse(t.sellDate.split('/')[1]) ?? 0;
      tp[m] = (tp[m] ?? 0) + (t.profit ?? 0);
    }
    return BizAnnualReport._(
        y, ts, [for (final m in s.months) if (m.year == y) m], tp, extra);
  }

  Iterable<PropertyTrade> get soldInYear =>
      trades.where((t) => t.sold && t.sellDate.startsWith('$year/'));
  double get soldProfit => soldInYear.fold(0.0, (a, t) => a + (t.profit ?? 0));

  double monthSum(double Function(BizMonth) f) =>
      months.fold(0.0, (a, m) => a + f(m));

  static const tradeHeaders = [
    'عنوان', 'تاریخ خرید', 'مبلغ خرید', 'تاریخ فروش', 'مبلغ فروش', 'متراژ',
    'کد و نقشه', 'روز', 'سود/زیان', 'درصد', 'یادداشت',
  ];
  static const monthHeaders = [
    'ماه', 'حقوق', 'PWO', 'تبلیغات', 'درآمد', 'خالص', 'سود معاملات فروخته‌شده',
  ];

  List<List<Object?>> tradeRows() => [
        for (final t in trades)
          [
            t.title, t.buyDate, t.buyAmount, t.sellDate.isEmpty ? null : t.sellDate,
            t.sold ? t.sellAmount : null, t.area, t.extraCost, t.days, t.profit,
            t.profitPct == null ? null : double.parse(t.profitPct!.toStringAsFixed(2)),
            t.note,
          ],
      ];

  List<List<Object?>> monthRows() => [
        for (final m in months)
          [
            _monthNames[m.month - 1], m.staff, m.pwo, m.ads, m.income, m.net,
            tradeProfitByMonth[m.month] ?? 0,
          ],
        [
          'جمع', monthSum((m) => m.staff), monthSum((m) => m.pwo),
          monthSum((m) => m.ads), monthSum((m) => m.income),
          monthSum((m) => m.net), soldProfit,
        ],
      ];

  String get fileStem => full ? 'گزارش-جامع-$year' : 'ملک-و-دفتر-$year';

  // ------------------------------------------------------------------ xlsx

  Uint8List toXlsx() {
    final sheets = <String, List<List<Object?>>>{
      ...extra,
      'معاملات ملک سال $year': [tradeHeaders, ...tradeRows(),
        if (trades.isNotEmpty) ['جمع سود فروخته‌شده در سال', null, null, null, null, null, null, null, soldProfit]],
      'جدول ماهانه $year': [monthHeaders, ...monthRows()],
    };
    final names = sheets.keys.toList();
    final a = Archive();
    void add(String n, String s) => a.addFile(ArchiveFile.bytes(n, utf8.encode(s)));
    const x = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n';
    add('[Content_Types].xml',
        '$x<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
        '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
        '<Default Extension="xml" ContentType="application/xml"/>'
        '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
        '<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>'
        '${[for (var i = 1; i <= names.length; i++) '<Override PartName="/xl/worksheets/sheet$i.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'].join()}'
        '</Types>');
    add('_rels/.rels',
        '$x<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>'
        '</Relationships>');
    add('xl/workbook.xml',
        '$x<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets>'
        '${[for (var i = 0; i < names.length; i++) '<sheet name="${_esc(names[i])}" sheetId="${i + 1}" r:id="rId${i + 1}"/>'].join()}'
        '</sheets></workbook>');
    add('xl/_rels/workbook.xml.rels',
        '$x<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '${[for (var i = 1; i <= names.length; i++) '<Relationship Id="rId$i" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet$i.xml"/>'].join()}'
        '<Relationship Id="rId${names.length + 1}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>'
        '</Relationships>');
    // style 0 normal, 1 bold header, 2 thousands number
    add('xl/styles.xml',
        '$x<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
        '<fonts count="2"><font><sz val="11"/><name val="Tahoma"/></font><font><b/><sz val="11"/><name val="Tahoma"/></font></fonts>'
        '<fills count="2"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill></fills>'
        '<borders count="1"><border/></borders><cellStyleXfs count="1"><xf/></cellStyleXfs>'
        '<cellXfs count="3"><xf fontId="0"/><xf fontId="1" applyFont="1"/><xf fontId="0" numFmtId="3" applyNumberFormat="1"/></cellXfs>'
        '</styleSheet>');
    for (var i = 0; i < names.length; i++) {
      final rows = sheets[names[i]]!;
      final b = StringBuffer('$x<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
          '<sheetViews><sheetView rightToLeft="1" workbookViewId="0"><pane ySplit="1" topLeftCell="A2" state="frozen"/></sheetView></sheetViews>'
          '<cols><col min="1" max="1" width="24" customWidth="1"/><col min="2" max="12" width="16" customWidth="1"/></cols><sheetData>');
      for (var r = 0; r < rows.length; r++) {
        final last = r == rows.length - 1 && (rows[r].isNotEmpty && '${rows[r][0]}'.startsWith('جمع'));
        b.write('<row r="${r + 1}">');
        for (var c = 0; c < rows[r].length; c++) {
          final v = rows[r][c];
          if (v == null) continue;
          final ref = '${_col(c)}${r + 1}';
          final bold = r == 0 || last;
          if (v is num) {
            b.write('<c r="$ref" s="${bold ? 1 : 2}"><v>${v is double && v == v.roundToDouble() ? v.toInt() : v}</v></c>');
          } else {
            final s = '$v';
            if (s.isEmpty) continue;
            b.write('<c r="$ref" t="inlineStr"${bold ? ' s="1"' : ''}><is><t>${_esc(s)}</t></is></c>');
          }
        }
        b.write('</row>');
      }
      b.write('</sheetData></worksheet>');
      add('xl/worksheets/sheet${i + 1}.xml', b.toString());
    }
    return ZipEncoder().encodeBytes(a);
  }

  static String _col(int i) {
    var n = i + 1, s = '';
    while (n > 0) {
      final m = (n - 1) % 26;
      s = String.fromCharCode(65 + m) + s;
      n = (n - 1) ~/ 26;
    }
    return s;
  }

  static String _esc(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');

  // ------------------------------------------------------------------- pdf

  /// The PDF shaper draws ZWNJ as a box; a thin space reads the same.
  static String _z(String s) => s.replaceAll('\u200c', '\u2009');

  static String _n(Object? v) {
    if (v == null) return '';
    if (v is double && v != v.roundToDouble() && v.abs() < 1000) {
      return v.toStringAsFixed(2);
    }
    if (v is num) {
      final neg = v < 0;
      final s = v.abs().round().toString().replaceAllMapped(
          RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
      return neg ? '-$s' : s;
    }
    return _z('$v');
  }

  Future<Uint8List> toPdf({required ByteData font, required ByteData bold}) {
    final doc = pw.Document(
      theme: pw.ThemeData.withFont(base: pw.Font.ttf(font), bold: pw.Font.ttf(bold)),
      title: fileStem,
    );
    pw.Widget table(List<String> h, List<List<Object?>> rows, {int? pctCol}) =>
        pw.TableHelper.fromTextArray(
          headers: [for (final x in h.reversed) _z(x)],
          data: [
            for (final r in rows)
              [
                for (var i = r.length - 1; i >= 0; i--)
                  pctCol == i && r[i] is num
                      ? (r[i] as num).toStringAsFixed(1)
                      : _n(r[i])
              ]
          ],
          headerDirection: pw.TextDirection.rtl,
          tableDirection: pw.TextDirection.rtl,
          headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8, color: PdfColors.white),
          headerDecoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFF1B5E40)),
          cellStyle: const pw.TextStyle(fontSize: 7.5),
          cellAlignment: pw.Alignment.centerRight,
          headerAlignment: pw.Alignment.centerRight,
          oddRowDecoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFF3F5F4)),
          border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.4),
          cellPadding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 2),
        );
    pw.Widget h2(String s) => pw.Padding(
        padding: const pw.EdgeInsets.only(top: 10, bottom: 6),
        child: pw.Text(_z(s), style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12)));
    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4.landscape,
      textDirection: pw.TextDirection.rtl,
      margin: const pw.EdgeInsets.all(24),
      footer: (c) => pw.Align(
          alignment: pw.Alignment.centerLeft,
          child: pw.Text('${c.pageNumber} / ${c.pagesCount}', style: const pw.TextStyle(fontSize: 8))),
      build: (c) => [
        pw.Text(_z(full ? 'گزارش جامع سالانه — سال $year (تا این لحظه)' : 'گزارش سالانهٔ ملک و دفتر — سال $year'),
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 16)),
        pw.SizedBox(height: 4),
        pw.Text(
            _z('سود معاملات فروخته‌شده در سال: ${_n(soldProfit)} تومان · خالص ماهانهٔ سال: ${_n(monthSum((m) => m.net))} تومان'),
            style: const pw.TextStyle(fontSize: 10)),
        for (final e in extra.entries)
          if (e.value.length > 1 || e.key == 'خلاصه') ...[
            h2(e.key),
            table([for (final x in e.value.first) '${x ?? ''}'], e.value.skip(1).toList()),
          ],
        h2('معاملات ملک (${trades.length})'),
        if (trades.isEmpty) pw.Text('معامله‌ای در این سال ثبت نشده.') else table(tradeHeaders, tradeRows(), pctCol: 9),
        h2('جدول ماهانه (تومان)'),
        table(monthHeaders, monthRows()),
      ],
    ));
    return doc.save();
  }
}

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:invest/domain/models/iran_inflation.dart';

/// Loads SCI monthly CPI/inflation from the Farmaanaa open dataset
/// (Hugging Face datasets-server), originally sourced from amar.org.ir.
class IranInflationService {
  IranInflationService({http.Client? client})
      : _client = client ?? http.Client();

  final http.Client _client;

  static const _dataset = 'Farmaanaa/iran_cpi_and_inflation_multisource';
  static const _rowsUrl =
      'https://datasets-server.huggingface.co/rows';

  Future<IranInflationSnapshot> fetchLatest({int historyMonths = 12}) async {
    final sizeProbe = await _getRows(offset: 0, length: 1);
    final total = (sizeProbe['num_rows_total'] as num?)?.toInt() ?? 0;
    if (total <= 0) {
      throw StateError('سری تورم در دسترس نیست.');
    }

    final need = (historyMonths + 6).clamp(12, 48);
    final offset = (total - need).clamp(0, total);
    final page = await _getRows(offset: offset, length: need);
    final rows = (page['rows'] as List?) ?? const [];

    final sci = <IranInflationPoint>[];
    for (final item in rows) {
      if (item is! Map) continue;
      final row = Map<String, dynamic>.from((item['row'] as Map?) ?? const {});
      if ((row['source_id'] as String?) != 'sci') continue;
      if ((row['freq'] as String?) != 'M') continue;
      final yoy = _num(row['inflation_yoy']);
      final mom = _num(row['inflation_mom']);
      final annual = _num(row['inflation_annual']);
      final cpi = _num(row['cpi_index']);
      if (yoy == null || mom == null || annual == null || cpi == null) continue;
      sci.add(
        IranInflationPoint(
          period: (row['period'] as String?) ?? '',
          year: (row['year'] as num?)?.toInt() ?? 0,
          month: (row['month'] as num?)?.round() ?? 0,
          cpiIndex: cpi,
          pointToPointPct: yoy,
          monthlyPct: mom,
          annualPct: annual,
        ),
      );
    }

    if (sci.isEmpty) {
      throw StateError('داده ماهانه مرکز آمار یافت نشد.');
    }

    sci.sort((a, b) {
      final byYear = a.year.compareTo(b.year);
      if (byYear != 0) return byYear;
      return a.month.compareTo(b.month);
    });

    final latest = sci.last;
    final hist = sci.length <= historyMonths
        ? List<IranInflationPoint>.from(sci)
        : sci.sublist(sci.length - historyMonths);

    return IranInflationSnapshot(
      period: latest.period,
      year: latest.year,
      month: latest.month,
      cpiIndex: latest.cpiIndex,
      pointToPointPct: latest.pointToPointPct,
      monthlyPct: latest.monthlyPct,
      annualPct: latest.annualPct,
      history: hist,
      sourceLabel: 'مرکز آمار ایران (SCI) — پایه ۱۴۰۰',
      fetchedAt: DateTime.now(),
      baseYear: 1400,
    );
  }

  Future<Map<String, dynamic>> _getRows({
    required int offset,
    required int length,
  }) async {
    final uri = Uri.parse(_rowsUrl).replace(queryParameters: {
      'dataset': _dataset,
      'config': 'mart',
      'split': 'train',
      'offset': '$offset',
      'length': '$length',
    });
    final res = await _client.get(uri).timeout(const Duration(seconds: 25));
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw StateError('HTTP ${res.statusCode} هنگام دریافت تورم');
    }
    final decoded = jsonDecode(utf8.decode(res.bodyBytes));
    if (decoded is! Map) {
      throw StateError('پاسخ نامعتبر تورم');
    }
    return Map<String, dynamic>.from(decoded);
  }

  static double? _num(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse('$v');
  }
}

import 'package:invest/data/invest_api_client.dart';
import 'package:invest/data/write_queue.dart';

/// Thin client for Vinor `/invest/api/v1/biz`. Every call returns the
/// server's full snapshot. Amounts are toman.
class BizRemote {
  BizRemote(this._api);
  final InvestApiClient _api;

  static const _base = '/invest/api/v1/biz';

  Map<String, dynamic> _snap(Map<String, dynamic> data) {
    final p = data['biz'];
    if (p is Map) return Map<String, dynamic>.from(p);
    throw InvestApiException('پاسخ سرور برای جدول کسب‌وکار نامعتبر است.');
  }

  Future<Map<String, dynamic>> fetch({int? year}) async => _snap(await _api
      .get(_base, query: year == null ? null : {'year': '$year'}));

  // Write requests (also used by the offline queue).
  static WriteRequest addTradeReq(Map<String, dynamic> body, {int? year}) =>
      WriteRequest('POST', '$_base/trades${_qs(year)}', body);
  static WriteRequest updateTradeReq(int id, Map<String, dynamic> body, {int? year}) =>
      WriteRequest('PATCH', '$_base/trades/$id${_qs(year)}', body);
  static WriteRequest deleteTradeReq(int id, {int? year}) =>
      WriteRequest('DELETE', '$_base/trades/$id${_qs(year)}');
  static WriteRequest putMonthReq(int year, int month, Map<String, dynamic> body) =>
      WriteRequest('PUT', '$_base/months/$year/$month', body);
  static WriteRequest deleteMonthReq(int year, int month) =>
      WriteRequest('DELETE', '$_base/months/$year/$month');
  static String _qs(int? year) => year == null ? '' : '?year=$year';

  /// Sends [r]; with [idempotencyKey] the server runs it at most once.
  Future<Map<String, dynamic>> run(WriteRequest r, {String? idempotencyKey}) async =>
      _snap(await _api.send(r.method, r.path, body: r.body, idempotencyKey: idempotencyKey));

  Future<Map<String, dynamic>> addTrade(Map<String, dynamic> body, {int? year}) =>
      run(addTradeReq(body, year: year));
  Future<Map<String, dynamic>> updateTrade(int id, Map<String, dynamic> body, {int? year}) =>
      run(updateTradeReq(id, body, year: year));
  Future<Map<String, dynamic>> deleteTrade(int id, {int? year}) =>
      run(deleteTradeReq(id, year: year));
  Future<Map<String, dynamic>> putMonth(int year, int month, Map<String, dynamic> body) =>
      run(putMonthReq(year, month, body));

  /// Guarded one-time import: the server writes nothing if the account
  /// already has trades or monthly rows. Returns the raw response.
  Future<Map<String, dynamic>> import(Map<String, dynamic> payload) =>
      _api.post('$_base/import', body: payload);

  /// All trades + all monthly rows (every year), import-ready.
  Future<Map<String, dynamic>> export() async {
    final d = await _api.get('$_base/export');
    final e = d['export'];
    if (e is Map) return Map<String, dynamic>.from(e);
    throw InvestApiException('پاسخ سرور برای پشتیبان ملک نامعتبر است.');
  }

  Future<Map<String, dynamic>> deleteMonth(int year, int month) =>
      run(deleteMonthReq(year, month));
}

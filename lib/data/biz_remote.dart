import 'package:invest/data/invest_api_client.dart';

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

  String _q(int? year) => year == null ? '' : '?year=$year';

  Future<Map<String, dynamic>> fetch({int? year}) async => _snap(await _api
      .get(_base, query: year == null ? null : {'year': '$year'}));

  Future<Map<String, dynamic>> addTrade(Map<String, dynamic> body,
          {int? year}) async =>
      _snap(await _api.post('$_base/trades${_q(year)}', body: body));

  Future<Map<String, dynamic>> updateTrade(int id, Map<String, dynamic> body,
          {int? year}) async =>
      _snap(await _api.patch('$_base/trades/$id${_q(year)}', body: body));

  Future<Map<String, dynamic>> deleteTrade(int id, {int? year}) async =>
      _snap(await _api.delete('$_base/trades/$id${_q(year)}'));

  Future<Map<String, dynamic>> putMonth(
          int year, int month, Map<String, dynamic> body) async =>
      _snap(await _api.put('$_base/months/$year/$month', body: body));

  Future<Map<String, dynamic>> deleteMonth(int year, int month) async =>
      _snap(await _api.delete('$_base/months/$year/$month'));
}

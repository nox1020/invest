import 'package:invest/data/invest_api_client.dart';

/// Thin client for Vinor `/invest/api/v1/pwo`. Every call returns the
/// server's full PWO snapshot. Amounts are toman on both sides.
class PwoRemote {
  PwoRemote(this._api);
  final InvestApiClient _api;

  static const _base = '/invest/api/v1/pwo';

  Map<String, dynamic> _snap(Map<String, dynamic> data) {
    final p = data['pwo'];
    if (p is Map) return Map<String, dynamic>.from(p);
    throw InvestApiException('پاسخ سرور برای PWO نامعتبر است.');
  }

  Future<Map<String, dynamic>> fetch() async => _snap(await _api.get(_base));

  Future<Map<String, dynamic>> import(Map<String, dynamic> payload) async =>
      _snap(await _api.post('$_base/import', body: payload));

  Future<Map<String, dynamic>> setTarget(double toman) async =>
      _snap(await _api.put('$_base/target', body: {'target': toman}));

  Future<Map<String, dynamic>> addWithdrawer(String name) async =>
      _snap(await _api.post('$_base/withdrawers', body: {'name': name}));

  Future<Map<String, dynamic>> patchWithdrawer(
    String id, {
    String? name,
    bool? archived,
  }) async =>
      _snap(await _api.patch('$_base/withdrawers/$id', body: {
        if (name != null) 'name': name,
        if (archived != null) 'archived': archived,
      }));

  Future<Map<String, dynamic>> deleteWithdrawer(String id) async =>
      _snap(await _api.delete('$_base/withdrawers/$id'));

  Future<Map<String, dynamic>> putMonth(
          int year, int month, Map<String, double> amounts) async =>
      _snap(await _api.put('$_base/months/$year/$month',
          body: {'amounts': amounts}));

  Future<Map<String, dynamic>> deleteEntry(int id) async =>
      _snap(await _api.delete('$_base/entries/$id'));
}

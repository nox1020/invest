import 'package:invest/data/invest_api_client.dart';
import 'package:invest/data/write_queue.dart';

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

  /// Raw response (keeps `already_has_data` / `written`).
  Future<Map<String, dynamic>> importRaw(Map<String, dynamic> payload) =>
      _api.post('$_base/import', body: payload);

  // Write requests (also used by the offline queue).
  static WriteRequest setTargetReq(double toman) =>
      WriteRequest('PUT', '$_base/target', {'target': toman});
  static WriteRequest addWithdrawerReq(String name) =>
      WriteRequest('POST', '$_base/withdrawers', {'name': name});
  static WriteRequest patchWithdrawerReq(String id, {String? name, bool? archived}) =>
      WriteRequest('PATCH', '$_base/withdrawers/$id', {
        if (name != null) 'name': name,
        if (archived != null) 'archived': archived,
      });
  static WriteRequest deleteWithdrawerReq(String id) =>
      WriteRequest('DELETE', '$_base/withdrawers/$id');
  static WriteRequest putMonthReq(int year, int month, Map<String, double> amounts) =>
      WriteRequest('PUT', '$_base/months/$year/$month', {'amounts': amounts});
  static WriteRequest deleteEntryReq(int id) =>
      WriteRequest('DELETE', '$_base/entries/$id');
  static WriteRequest addTxReq(
          String withdrawerId, int year, int month, double toman, String note) =>
      WriteRequest('POST', '$_base/transactions', {
        'withdrawer_id': int.tryParse(withdrawerId) ?? withdrawerId,
        'year': year,
        'month': month,
        'amount': toman,
        'note': note,
      });
  static WriteRequest patchTxReq(int id, String withdrawerId, double toman, String note) =>
      WriteRequest('PATCH', '$_base/transactions/$id', {
        'withdrawer_id': int.tryParse(withdrawerId) ?? withdrawerId,
        'amount': toman,
        'note': note,
      });
  static WriteRequest deleteTxReq(int id) =>
      WriteRequest('DELETE', '$_base/transactions/$id');

  /// Sends [r]; with [idempotencyKey] the server runs it at most once.
  Future<Map<String, dynamic>> run(WriteRequest r, {String? idempotencyKey}) async =>
      _snap(await _api.send(r.method, r.path, body: r.body, idempotencyKey: idempotencyKey));

  Future<Map<String, dynamic>> setTarget(double toman) => run(setTargetReq(toman));
  Future<Map<String, dynamic>> addWithdrawer(String name) => run(addWithdrawerReq(name));
  Future<Map<String, dynamic>> patchWithdrawer(String id, {String? name, bool? archived}) =>
      run(patchWithdrawerReq(id, name: name, archived: archived));
  Future<Map<String, dynamic>> deleteWithdrawer(String id) => run(deleteWithdrawerReq(id));
  Future<Map<String, dynamic>> putMonth(int year, int month, Map<String, double> amounts) =>
      run(putMonthReq(year, month, amounts));
  Future<Map<String, dynamic>> deleteEntry(int id) => run(deleteEntryReq(id));
  Future<Map<String, dynamic>> addTx(
          String withdrawerId, int year, int month, double toman, String note) =>
      run(addTxReq(withdrawerId, year, month, toman, note));
  Future<Map<String, dynamic>> patchTx(int id, String withdrawerId, double toman, String note) =>
      run(patchTxReq(id, withdrawerId, toman, note));
  Future<Map<String, dynamic>> deleteTx(int id) => run(deleteTxReq(id));
}

import 'package:invest/data/invest_api_client.dart';
import 'package:invest/data/write_queue.dart';

/// Thin client for Vinor `/invest/api/v1/projects` (پروژه‌ها / پیمانکاری).
/// Every write returns the server's full snapshot. Amounts are toman.
class ProjectsRemote {
  ProjectsRemote(this._api);
  final InvestApiClient _api;

  static const base = '/invest/api/v1/projects';

  Map<String, dynamic> _snap(Map<String, dynamic> data) {
    final p = data['projects'];
    if (p is Map) return Map<String, dynamic>.from(p);
    throw InvestApiException('پاسخ سرور برای پروژه‌ها نامعتبر است.');
  }

  Future<Map<String, dynamic>> fetch() async => _snap(await _api.get(base));

  // Write requests (also used by the offline queue).
  static WriteRequest addReq(Map<String, dynamic> body) =>
      WriteRequest('POST', base, body);
  static WriteRequest updateReq(int id, Map<String, dynamic> body) =>
      WriteRequest('PATCH', '$base/$id', body);
  static WriteRequest deleteReq(int id) => WriteRequest('DELETE', '$base/$id');

  /// Sends [r]; with [idempotencyKey] the server runs it at most once.
  Future<Map<String, dynamic>> run(WriteRequest r, {String? idempotencyKey}) async =>
      _snap(await _api.send(r.method, r.path, body: r.body, idempotencyKey: idempotencyKey));

  /// Append-only import: rows already on the server are skipped, nothing is
  /// overwritten. Returns the raw response (`written`, `skipped`, `projects`).
  Future<Map<String, dynamic>> import(Map<String, dynamic> payload) =>
      _api.post('$base/import', body: payload);

  /// Every project (archived too), import-ready.
  Future<Map<String, dynamic>> export() async {
    final d = await _api.get('$base/export');
    final e = d['export'];
    if (e is Map) return Map<String, dynamic>.from(e);
    throw InvestApiException('پاسخ سرور برای پشتیبان پروژه‌ها نامعتبر است.');
  }
}

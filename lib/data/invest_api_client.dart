import 'dart:convert';

import 'package:http/http.dart' as http;

import 'package:invest/data/session_store.dart';

class InvestApiException implements Exception {
  InvestApiException(this.message, {this.statusCode, this.errorCode});

  final String message;
  final int? statusCode;
  final String? errorCode;

  @override
  String toString() => message;
}

/// Result of session validation — distinguishes offline from logged-out.
enum AuthCheckStatus { authenticated, unauthenticated, offline }

class AuthCheckResult {
  const AuthCheckResult(this.status);
  final AuthCheckStatus status;
  bool get isAuthenticated =>
      status == AuthCheckStatus.authenticated ||
      status == AuthCheckStatus.offline;
  bool get isOffline => status == AuthCheckStatus.offline;
}

/// HTTP client for Vinor auth + Invest REST API with cookie session.
class InvestApiClient {
  InvestApiClient(
    this._session, {
    http.Client? client,
    this.timeout = const Duration(seconds: 10),
  }) : _client = client ?? http.Client();

  final SessionStore _session;
  final http.Client _client;
  final Duration timeout;

  String? _sessionCookie;

  String get baseUrl => _session.baseUrl;

  bool get hasSessionCookie {
    restoreSessionCookie();
    return _sessionCookie != null && _sessionCookie!.isNotEmpty;
  }

  void restoreSessionCookie() {
    _sessionCookie = _session.sessionCookie;
  }

  Future<Map<String, dynamic>> get(String path, {Map<String, String>? query}) {
    final uri = _uri(path, query: query);
    return _request('GET', uri);
  }

  Future<Map<String, dynamic>> post(String path, {Map<String, dynamic>? body}) {
    return _request('POST', _uri(path), body: body);
  }

  Future<Map<String, dynamic>> put(String path, {Map<String, dynamic>? body}) {
    return _request('PUT', _uri(path), body: body);
  }

  Future<Map<String, dynamic>> patch(String path,
      {Map<String, dynamic>? body}) {
    return _request('PATCH', _uri(path), body: body);
  }

  Future<Map<String, dynamic>> delete(String path) {
    return _request('DELETE', _uri(path));
  }

  Uri _uri(String path, {Map<String, String>? query}) {
    final p = path.startsWith('/') ? path : '/$path';
    return Uri.parse('$baseUrl$p').replace(queryParameters: query);
  }

  Future<Map<String, dynamic>> _request(
    String method,
    Uri uri, {
    Map<String, dynamic>? body,
  }) async {
    final headers = <String, String>{
      'Accept': 'application/json',
      if (body != null) 'Content-Type': 'application/json; charset=utf-8',
      if (_sessionCookie != null && _sessionCookie!.isNotEmpty)
        'Cookie': _sessionCookie!,
    };

    try {
      late http.Response response;
      switch (method) {
        case 'GET':
          response = await _client.get(uri, headers: headers).timeout(timeout);
        case 'POST':
          response = await _client
              .post(
                uri,
                headers: headers,
                body: body == null ? null : jsonEncode(body),
              )
              .timeout(timeout);
        case 'PUT':
          response = await _client
              .put(
                uri,
                headers: headers,
                body: body == null ? null : jsonEncode(body),
              )
              .timeout(timeout);
        case 'PATCH':
          response = await _client
              .patch(
                uri,
                headers: headers,
                body: body == null ? null : jsonEncode(body),
              )
              .timeout(timeout);
        case 'DELETE':
          response =
              await _client.delete(uri, headers: headers).timeout(timeout);
        default:
          throw InvestApiException('متد HTTP پشتیبانی نمی‌شود: $method');
      }

      await _captureSessionCookie(response);
      return _parseJson(response);
    } on InvestApiException {
      rethrow;
    } catch (e) {
      throw InvestApiException(
        'ارتباط با سرور برقرار نشد (آفلاین).',
        statusCode: null,
        errorCode: 'network_error',
      );
    }
  }

  Future<void> _captureSessionCookie(http.Response response) async {
    final raw = response.headers['set-cookie'];
    if (raw == null || raw.isEmpty) return;
    final match = RegExp(r'vinor_session=([^;,\s]+)').firstMatch(raw);
    if (match == null) return;
    _sessionCookie = 'vinor_session=${match.group(1)}';
    await _session.setSessionCookie(_sessionCookie);
  }

  String _fallbackHttpError(int statusCode) {
    if (statusCode == 404) return 'مورد درخواستی در سرور یافت نشد.';
    if (statusCode == 405) return 'این عملیات در سرور پشتیبانی نمی‌شود.';
    return 'خطا در ارتباط با سرور.';
  }

  Map<String, dynamic> _parseJson(http.Response response) {
    Map<String, dynamic> data;
    try {
      final decoded = jsonDecode(response.body);
      data = decoded is Map<String, dynamic>
          ? decoded
          : <String, dynamic>{'success': response.statusCode < 400};
    } catch (_) {
      throw InvestApiException(
        'پاسخ سرور نامعتبر است (${response.statusCode}).',
        statusCode: response.statusCode,
      );
    }

    if (response.statusCode == 401) {
      throw InvestApiException(
        (data['message'] as String?) ?? 'ابتدا وارد شوید.',
        statusCode: 401,
        errorCode: (data['error'] as String?) ?? 'auth_required',
      );
    }

    if (response.statusCode >= 400 || data['success'] == false) {
      final message = (data['message'] as String?)?.trim();
      throw InvestApiException(
        (message != null && message.isNotEmpty)
            ? message
            : _fallbackHttpError(response.statusCode),
        statusCode: response.statusCode,
        errorCode: data['error'] as String?,
      );
    }

    return data;
  }

  Future<String?> requestOtp(String phone) async {
    final data = await post('/auth/request-otp', body: {'phone': phone});
    return data['debug_code'] as String?;
  }

  Future<void> verifyOtp(String phone, String code) async {
    await post('/auth/verify-otp', body: {'phone': phone, 'code': code});
    await _session.setPhone(phone);
  }

  Future<bool> checkAuth() async {
    final result = await checkAuthDetailed();
    return result.status == AuthCheckStatus.authenticated;
  }

  Future<AuthCheckResult> checkAuthDetailed() async {
    restoreSessionCookie();
    if (_sessionCookie == null || _sessionCookie!.isEmpty) {
      return const AuthCheckResult(AuthCheckStatus.unauthenticated);
    }
    try {
      final data = await get('/invest/api/v1/auth/status');
      if (data['authenticated'] == true) {
        return const AuthCheckResult(AuthCheckStatus.authenticated);
      }
      return const AuthCheckResult(AuthCheckStatus.unauthenticated);
    } on InvestApiException catch (e) {
      if (e.statusCode == 401) {
        return const AuthCheckResult(AuthCheckStatus.unauthenticated);
      }
      // Network / timeout / server unreachable — keep local session.
      return const AuthCheckResult(AuthCheckStatus.offline);
    }
  }

  Future<void> logout() async {
    _sessionCookie = null;
    await _session.clearAuth();
  }

  Future<String?> fetchApiVersion() async {
    final data = await get('/invest/api/v1/health');
    final v = data['api_version'];
    return v?.toString();
  }
}

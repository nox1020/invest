import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:invest/data/bank_sms_store.dart';
import 'package:invest/data/pwo_store.dart';
import 'package:invest/domain/models/ai_audit_report.dart';
import 'package:invest/domain/models/asset.dart';
import 'package:invest/domain/services/ai_accountant_engine.dart';
import 'package:invest/domain/services/notification_service.dart';
import 'package:invest/state/app_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String kGeminiApiKeyPref = 'gemini_api_key';
const String kLegacyReportCacheKey = 'ai_accountant_daily_report_v1';
const String kGeminiConsentPrefix = 'ai_accountant_gemini_consent_v1_';
const String kCheckDigestPrefix = 'ai_check_digest_v1_';

String aiAuditCachePrefsKey(String accountKey) {
  final safe = accountKey.trim().isEmpty ? 'local' : accountKey.trim();
  return 'ai_accountant_report_v2_$safe';
}

String aiConsentPrefsKey(String accountKey) {
  final safe = accountKey.trim().isEmpty ? 'local' : accountKey.trim();
  return '$kGeminiConsentPrefix$safe';
}

String aiDigestPrefsKey(String accountKey) {
  final safe = accountKey.trim().isEmpty ? 'local' : accountKey.trim();
  return '$kCheckDigestPrefix$safe';
}

abstract class GeminiKeyVault {
  Future<String?> read();
  Future<void> write(String value);
  Future<void> delete();
}

class SecureGeminiKeyVault implements GeminiKeyVault {
  SecureGeminiKeyVault({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
            );

  static const storageKey = 'gemini_api_key_v1';
  final FlutterSecureStorage _storage;

  @override
  Future<String?> read() async {
    if (Platform.environment['FLUTTER_TEST'] == 'true') return null;
    try {
      return await _storage.read(key: storageKey);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> write(String value) async {
    if (Platform.environment['FLUTTER_TEST'] == 'true') return;
    try {
      await _storage.write(key: storageKey, value: value);
    } catch (_) {}
  }

  @override
  Future<void> delete() async {
    if (Platform.environment['FLUTTER_TEST'] == 'true') return;
    try {
      await _storage.delete(key: storageKey);
    } catch (_) {}
  }
}

class AiHttpResult {
  const AiHttpResult(this.status, this.body);
  final int status;
  final String body;
}

typedef AiHttpPoster = Future<AiHttpResult> Function({
  required Uri url,
  required Map<String, String> headers,
  required String body,
});

typedef CheckDigestSink = Future<void> Function(
    String title, String body, int id);

class AiAuditCacheRecord {
  const AiAuditCacheRecord({
    required this.accountKey,
    required this.day,
    required this.inputHash,
    required this.report,
  });

  final String accountKey;
  final String day;
  final String inputHash;
  final AiAuditReport report;

  bool matches(AiAuditSnapshot snap) =>
      accountKey == snap.accountKey &&
      day == snap.dayIso &&
      inputHash == snap.inputHash;
}

/// Daily accountant. The on-device rules run unless consent and a key exist.
class AiAccountantService {
  AiAccountantService({
    GeminiKeyVault? vault,
    Future<SharedPreferences> Function()? prefs,
    AiHttpPoster? post,
    CheckDigestSink? notifyChecks,
    this.clock,
  })  : _vault = vault ?? SecureGeminiKeyVault(),
        _prefs = prefs ?? SharedPreferences.getInstance,
        _post = post ?? _defaultPost,
        _notifyChecks = notifyChecks;

  static final AiAccountantService instance = AiAccountantService();

  static const geminiModel = 'gemini-2.5-flash';
  static final geminiUri = Uri.parse(
    'https://generativelanguage.googleapis.com/v1beta/models/$geminiModel:generateContent',
  );

  final GeminiKeyVault _vault;
  final Future<SharedPreferences> Function() _prefs;
  final AiHttpPoster _post;
  final CheckDigestSink? _notifyChecks;
  final DateTime Function()? clock;

  final Map<String, Future<AiAuditReport>> _inflight = {};
  Future<String>? _geminiFlight;
  String? _geminiFlightHash;

  DateTime get _now => clock?.call() ?? DateTime.now();

  AiAuditInput capture(AppState state) {
    PwoStore? pwoStore;
    var sms = 0;
    try {
      pwoStore = PwoStore.instance;
    } catch (_) {}
    try {
      sms = BankSmsStore.instance.pending.length;
    } catch (_) {}
    final metric = state.metrics?.totalValue ?? 0;
    final summed = state.assets.fold<double>(
      0,
      (sum, Asset asset) => sum + (asset.totalValue > 0 ? asset.totalValue : 0),
    );
    return AiAuditInput(
      now: _now,
      accountKey: (state.userPhone ?? '').trim(),
      totalCapitalToman: metric > 0 ? metric : summed,
      assets: state.assets,
      checks: state.checks,
      openTrades: state.openTrades,
      closedTrades: state.closedTrades,
      withdrawals: state.withdrawals,
      pwo: (pwoStore != null && pwoStore.loaded) ? pwoStore.ledger : null,
      unhandledSms: sms,
    );
  }

  Future<AiAuditReport> auditAccounts({
    required AppState state,
    bool force = false,
  }) {
    return audit(
      capture(state),
      force: force,
      notificationsEnabled: state.settings.notificationsEnabled,
    );
  }

  Future<AiAuditReport> audit(
    AiAuditInput input, {
    bool force = false,
    bool notificationsEnabled = false,
  }) {
    final snap = aggregateAudit(input);
    final key = '${snap.inputHash}|${force ? 'f' : 'c'}';
    final existing = _inflight[key];
    if (existing != null) return existing;
    final future =
        _audit(snap, force: force, notificationsEnabled: notificationsEnabled);
    _inflight[key] = future;
    return future.whenComplete(() {
      if (identical(_inflight[key], future)) _inflight.remove(key);
    });
  }

  Future<AiAuditCacheRecord?> readCache(String accountKey) async {
    try {
      final prefs = await _prefs();
      final raw = prefs.getString(aiAuditCachePrefsKey(accountKey));
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final map = Map<String, dynamic>.from(decoded);
      final report = AiAuditReport.fromJson(_map(map['report']));
      final record = AiAuditCacheRecord(
        accountKey: map['account']?.toString() ?? report.accountKey,
        day: map['day']?.toString() ?? report.dayIso,
        inputHash: map['hash']?.toString() ?? report.inputHash,
        report: report,
      );
      if (record.accountKey != accountKey.trim()) return null;
      return record;
    } catch (_) {
      return null;
    }
  }

  Future<bool> hasConsent(String accountKey) async {
    try {
      final prefs = await _prefs();
      return prefs.getBool(aiConsentPrefsKey(accountKey)) ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> setConsent(String accountKey, bool value) async {
    final prefs = await _prefs();
    await prefs.setBool(aiConsentPrefsKey(accountKey), value);
  }

  Future<bool> geminiReady(String accountKey) async {
    if (!await hasConsent(accountKey)) return false;
    return (await readApiKey()).isNotEmpty;
  }

  Future<String> readApiKey() async {
    return migrateAndReadGeminiKey(vault: _vault, prefs: await _prefs());
  }

  Future<void> saveApiKey(String key) async {
    final trimmed = key.trim();
    final prefs = await _prefs();
    if (trimmed.isEmpty) {
      await _vault.delete();
    } else {
      await _vault.write(trimmed);
    }
    if (prefs.containsKey(kGeminiApiKeyPref)) {
      await prefs.remove(kGeminiApiKeyPref);
    }
  }

  Future<String?> rephrase(AppState state, String redactedAnswer) async {
    final input = capture(state);
    if (!await hasConsent(input.accountKey)) return null;
    final key = await readApiKey();
    if (key.isEmpty) return null;
    final snap = aggregateAudit(input);
    final payload = {
      'aggregates': redactedAuditPayload(snap),
      'answer': redactedAnswer,
    };
    try {
      final text = await _generate(
        key,
        'فقط پاسخ داده‌شده را به فارسی روان و رسمی بازنویس. عدد، نام یا سند تازه‌ای نساز. '
        'اگر نام شخص یا شماره چک در پاسخ نیست، اضافه نکن. خروجی فقط خود متن باشد.\n'
        '${jsonEncode(payload)}',
        jsonMode: false,
      );
      final cleaned = text.trim();
      if (cleaned.isEmpty) return null;
      return cleaned;
    } catch (error) {
      debugPrint('Gemini rephrase skipped: $error');
      return null;
    }
  }

  Future<AiAuditReport> _audit(
    AiAuditSnapshot snap, {
    required bool force,
    required bool notificationsEnabled,
  }) async {
    if (!force) {
      final cached = await readCache(snap.accountKey);
      if (cached != null && cached.matches(snap)) return cached.report;
    }

    var report = buildLocalReport(snap);
    final consent = await hasConsent(snap.accountKey);
    final apiKey = consent ? await readApiKey() : '';
    if (consent && apiKey.isNotEmpty) {
      try {
        final narrative = await _narrative(snap, apiKey);
        if (narrative == null) {
          report = report.copyWithNarrative(
            fallbackReason: 'ساختار پاسخ جمنای با گزارش حسابرسی جور نبود.',
          );
        } else {
          report = applyGeminiNarrative(report, narrative);
        }
      } catch (error) {
        report = report.copyWithNarrative(fallbackReason: _geminiReason(error));
      }
    }

    await _writeCache(snap, report);
    await _maybeNotify(snap, notificationsEnabled);
    return report;
  }

  Future<void> _maybeNotify(AiAuditSnapshot snap, bool enabled) async {
    try {
      final prefs = await _prefs();
      final previous = prefs.getString(aiDigestPrefsKey(snap.accountKey));
      final plan = planCheckDigest(
        snap: snap,
        notificationsEnabled: enabled,
        previousFingerprint: previous,
      );
      if (!plan.shouldSend) return;
      for (final item in plan.items) {
        final sink = _notifyChecks;
        if (sink != null) {
          await sink(item.title, item.body, item.id);
        } else if (Platform.environment['FLUTTER_TEST'] != 'true') {
          await NotificationService.instance.show(
            title: item.title,
            body: item.body,
            kind: NotificationKind.checks,
            id: item.id,
          );
        }
      }
      await prefs.setString(
          aiDigestPrefsKey(snap.accountKey), plan.fingerprint);
    } catch (error) {
      debugPrint('Check digest skipped: $error');
    }
  }

  Future<void> _writeCache(AiAuditSnapshot snap, AiAuditReport report) async {
    try {
      final prefs = await _prefs();
      await prefs.setString(
        aiAuditCachePrefsKey(snap.accountKey),
        jsonEncode({
          'account': snap.accountKey,
          'day': snap.dayIso,
          'hash': snap.inputHash,
          'report': report.toJson(),
        }),
      );
      if (prefs.containsKey(kLegacyReportCacheKey)) {
        await prefs.remove(kLegacyReportCacheKey);
      }
    } catch (error) {
      debugPrint('Audit cache write skipped: $error');
    }
  }

  Future<GeminiNarrative?> _narrative(AiAuditSnapshot snap, String apiKey) {
    final hash = snap.inputHash;
    if (_geminiFlight != null && _geminiFlightHash == hash) {
      return _geminiFlight!.then(parseGeminiNarrative);
    }
    _geminiFlightHash = hash;
    final flight = _generate(
      apiKey,
      _auditPrompt(redactedAuditPayload(snap)),
      jsonMode: true,
    );
    _geminiFlight = flight;
    return flight.then(parseGeminiNarrative).whenComplete(() {
      if (identical(_geminiFlight, flight)) {
        _geminiFlight = null;
        _geminiFlightHash = null;
      }
    });
  }

  Future<String> _generate(
    String apiKey,
    String prompt, {
    required bool jsonMode,
  }) async {
    final result = await _post(
      url: geminiUri,
      headers: {
        'Content-Type': 'application/json',
        'x-goog-api-key': apiKey,
      },
      body: jsonEncode({
        'contents': [
          {
            'parts': [
              {'text': prompt},
            ],
          },
        ],
        if (jsonMode)
          'generationConfig': {'responseMimeType': 'application/json'},
      }),
    );
    if (result.status != 200) {
      throw GeminiAuditException('سرویس جمنای پاسخ معتبر نداد.');
    }
    final decoded = jsonDecode(result.body);
    if (decoded is! Map) {
      throw GeminiAuditException('پاسخ جمنای قابل خواندن نبود.');
    }
    final candidates = decoded['candidates'];
    if (candidates is! List || candidates.isEmpty) {
      throw GeminiAuditException('پاسخ جمنای قابل خواندن نبود.');
    }
    final first = candidates.first;
    if (first is! Map) {
      throw GeminiAuditException('پاسخ جمنای قابل خواندن نبود.');
    }
    final parts = first['content'];
    final text = parts is Map ? parts['parts'] : null;
    if (text is! List || text.isEmpty || text.first is! Map) {
      throw GeminiAuditException('پاسخ جمنای قابل خواندن نبود.');
    }
    return text.first['text']?.toString() ?? '';
  }

  static Future<AiHttpResult> _defaultPost({
    required Uri url,
    required Map<String, String> headers,
    required String body,
  }) async {
    final response = await http
        .post(url, headers: headers, body: body)
        .timeout(const Duration(seconds: 25));
    return AiHttpResult(response.statusCode, response.body);
  }
}

class GeminiAuditException implements Exception {
  GeminiAuditException(this.message);
  final String message;
  @override
  String toString() => message;
}

String _geminiReason(Object error) {
  if (error is GeminiAuditException) return error.message;
  return 'ارتباط با جمنای برقرار نشد.';
}

String _auditPrompt(Map<String, dynamic> data) {
  return '''
شما حسابرس مالی نرم‌افزار V+ هستید. فقط جمع‌های بی‌نام زیر را دارید. نام دارایی، نام شخص و شماره چک در داده نیست و نباید بسازید.
داده:
${jsonEncode(data)}
خروجی فقط یک شیء JSON با این کلیدها باشد:
{
  "health_score": <عدد صحیح ۰ تا ۱۰۰>,
  "health_title": "<عنوان کوتاه فارسی>",
  "summary": "<دو پاراگراف فارسی که همان اعداد داده را تکرار می‌کند>",
  "recommendations": ["<توصیه>", "<توصیه>", "<توصیه>"]
}
گروه cash با برچسب «نقد / تتر» را موجودی ریالی حساب بانکی فرض نکنید.
''';
}

Future<String> migrateAndReadGeminiKey({
  required GeminiKeyVault vault,
  required SharedPreferences prefs,
}) async {
  final secure = (await vault.read())?.trim() ?? '';
  final legacy = prefs.getString(kGeminiApiKeyPref)?.trim() ?? '';
  if (secure.isNotEmpty) {
    if (prefs.containsKey(kGeminiApiKeyPref)) {
      await prefs.remove(kGeminiApiKeyPref);
    }
    return secure;
  }
  if (legacy.isNotEmpty) {
    await vault.write(legacy);
    await prefs.remove(kGeminiApiKeyPref);
    return legacy;
  }
  return '';
}

Map<String, dynamic> _map(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return Map<String, dynamic>.from(value);
  return const {};
}

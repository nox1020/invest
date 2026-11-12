import 'package:flutter/foundation.dart';
import 'package:invest/domain/models/ai_audit_report.dart';
import 'package:invest/domain/services/ai_accountant_service.dart';
import 'package:invest/domain/utils/dates.dart';
import 'package:invest/state/app_state.dart';

/// Shared report so the dashboard card and the sheet stay on one audit.
class AiAccountantController extends ChangeNotifier {
  AiAccountantController({AiAccountantService? service})
      : service = service ?? AiAccountantService.instance;

  static final AiAccountantController instance = AiAccountantController();

  final AiAccountantService service;

  AiAuditReport? report;
  bool loading = false;
  bool stale = false;
  bool geminiReady = false;
  String? error;

  Future<void>? _run;
  bool _runForce = false;
  int _epoch = 0;

  Future<void> load(AppState state, {bool force = false}) {
    if (_run != null && (!force || _runForce)) return _run!;
    _runForce = force;
    final run = _load(state, force: force);
    _run = run;
    return run.whenComplete(() {
      if (identical(_run, run)) _run = null;
    });
  }

  Future<void> _load(AppState state, {required bool force}) async {
    final token = ++_epoch;
    final account = (state.userPhone ?? '').trim();
    final today = toIsoDate(DateTime.now());
    final cached = await service.readCache(account);
    if (token != _epoch) return;
    if (cached != null && cached.day != today) {
      report = cached.report;
      stale = true;
      error = null;
      notifyListeners();
    }
    loading = true;
    error = null;
    notifyListeners();
    try {
      final next = await service.auditAccounts(state: state, force: force);
      if (token != _epoch) return;
      report = next;
      stale = next.dayIso != today;
      error = null;
      geminiReady = await service.geminiReady(account);
    } catch (error) {
      if (token != _epoch) return;
      this.error = 'به‌روزرسانی گزارش انجام نشد.';
      debugPrint('Accountant load failed: $error');
      if (report != null && report!.dayIso != today) stale = true;
    } finally {
      if (token == _epoch) {
        loading = false;
        notifyListeners();
      }
    }
  }
}

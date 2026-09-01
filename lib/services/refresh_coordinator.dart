import 'dart:async';

/// Merged refresh intent for coalesced runs.
class RefreshPlan {
  RefreshPlan({
    this.includeQuotes = false,
    this.fetchSettings = true,
    this.checkApiVersion = true,
  });

  bool includeQuotes;
  bool fetchSettings;
  bool checkApiVersion;

  RefreshPlan merge(RefreshPlan other) {
    includeQuotes = includeQuotes || other.includeQuotes;
    // Skip optional work if any caller opted out (e.g. after saveSettings).
    fetchSettings = fetchSettings && other.fetchSettings;
    checkApiVersion = checkApiVersion && other.checkApiVersion;
    return this;
  }
}

/// Coalesces overlapping refresh requests (pull-to-refresh, toolbar, Vinor resume).
class RefreshCoordinator {
  Future<void>? _active;
  RefreshPlan? _pending;

  bool get isRunning => _active != null;

  Future<void> run(
    Future<void> Function(RefreshPlan plan) action, {
    bool includeQuotes = false,
    bool fetchSettings = true,
    bool checkApiVersion = true,
  }) {
    final plan = RefreshPlan(
      includeQuotes: includeQuotes,
      fetchSettings: fetchSettings,
      checkApiVersion: checkApiVersion,
    );
    if (_active != null) {
      _pending = (_pending ?? RefreshPlan()).merge(plan);
      return _active!;
    }
    _pending = plan;
    _active = _drain(action).whenComplete(() => _active = null);
    return _active!;
  }

  Future<void> _drain(
    Future<void> Function(RefreshPlan plan) action,
  ) async {
    while (_pending != null) {
      final plan = _pending!;
      _pending = null;
      await action(plan);
    }
  }
}

/// Debounce rapid resume events (e.g. returning from Vinor WebView shell).
class ResumeRefreshDebouncer {
  ResumeRefreshDebouncer({this.delay = const Duration(milliseconds: 700)});

  final Duration delay;
  Timer? _timer;

  void schedule(void Function() onFire) {
    _timer?.cancel();
    _timer = Timer(delay, onFire);
  }

  void dispose() => _timer?.cancel();
}

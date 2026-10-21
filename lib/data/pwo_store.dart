import 'package:flutter/foundation.dart';

import 'package:invest/data/local_platform.dart';
import 'package:invest/domain/services/pwo_ledger.dart';

/// Device-local PWO ledger (separate key; never touches other app data).
class PwoStore extends ChangeNotifier {
  PwoStore._();
  static final PwoStore instance = PwoStore._();

  static const prefsKey = 'vplus_pwo_ledger_v1';

  PwoLedger _ledger = PwoLedger();
  bool _loaded = false;
  PwoLedger get ledger => _ledger;
  bool get loaded => _loaded;

  Future<void> load() async {
    if (_loaded) return;
    final prefs = await LocalPrefs.open();
    final raw = prefs?.getString(prefsKey);
    _ledger = PwoLedger.decode(raw);
    _loaded = true;
    if (_ledger.applySeed()) await _save();
    notifyListeners();
  }

  Future<void> _save() async {
    final prefs = await LocalPrefs.open();
    if (prefs == null) return;
    await LocalPrefs.setString(prefs, prefsKey, _ledger.encode());
  }

  Future<void> saveMonth(PwoMonth m) async {
    _ledger.upsert(m);
    notifyListeners();
    await _save();
  }

  Future<void> deleteMonth(int year, int month) async {
    _ledger.remove(year, month);
    notifyListeners();
    await _save();
  }

  Future<void> setTarget(double v) async {
    if (!v.isFinite || v <= 0) return;
    _ledger.target = v;
    notifyListeners();
    await _save();
  }

  Future<void> setName(int i, String name) async {
    final s = name.trim();
    if (i < 0 || i > 2 || s.isEmpty) return;
    _ledger.names[i] = s;
    notifyListeners();
    await _save();
  }

  @visibleForTesting
  void debugReset() {
    _ledger = PwoLedger();
    _loaded = false;
  }
}

import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:invest/config/app_config.dart';
import 'package:invest/data/invest_api_client.dart';
import 'package:invest/data/pwo_remote.dart';
import 'package:invest/data/pwo_store.dart';
import 'package:invest/data/write_queue.dart';
import 'package:invest/data/session_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'pwo_remote_test.dart' show FakePwoServer;

/// Server account with months 1..9 of 1405 for three people.
FakePwoServer serverWith9Months({List<String> names = const ['M', 'A', 'N']}) {
  // Old server behaviour (no import guard): proves the app alone is safe.
  final s = FakePwoServer()..importGuard = false;
  final ids = <int>[];
  for (final n in names) {
    ids.add(s.addWithdrawerForTest(n));
  }
  for (var m = 1; m <= 9; m++) {
    for (var i = 0; i < ids.length; i++) {
      s.addEntryForTest(ids[i], 1405, m, (m * 1000000 + i).toDouble());
    }
  }
  return s;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<PwoRemote> remoteFor(FakePwoServer s) async {
    final session = await SessionStore.load();
    final api = InvestApiClient(session, client: MockClient(s.handle));
    api.restoreSessionCookie();
    return PwoRemote(api);
  }

  void freshInstall([Map<String, Object> extra = const {}]) {
    SharedPreferences.setMockInitialValues({
      AppConfig.prefBaseUrl: 'https://vinor.test',
      AppConfig.prefSessionCookie: 'vinor_session=t',
      ...extra,
    });
    PwoStore.instance.debugReset();
  }

  void expectIntact(FakePwoServer s, int people) {
    expect(s.ws.length, people);
    expect(s.es.length, people * 9);
    for (var m = 1; m <= 9; m++) {
      expect(s.es.where((e) => e['month'] == m).length, people);
    }
    final l = PwoStore.instance.ledger;
    expect(l.monthsOf(1405).length, 9);
    expect(l.monthsOf(1405).map((e) => e.month), [1, 2, 3, 4, 5, 6, 7, 8, 9]);
  }

  test('reinstall (empty storage) keeps server months 1-9, no duplicates',
      () async {
    freshInstall();
    final s = serverWith9Months();
    await PwoStore.instance.bindAccount(await remoteFor(s), '0912');
    expectIntact(s, 3);
    expect(s.calls.contains('POST /import'), isFalse,
        reason: 'server already has data -> never import the seed');
  });

  test('reinstall with renamed withdrawers: seed must not create M/A/N again',
      () async {
    freshInstall();
    final s = serverWith9Months(names: ['Masoud', 'Ali', 'Nima']);
    await PwoStore.instance.bindAccount(await remoteFor(s), '0912');
    expectIntact(s, 3);
    expect(PwoStore.instance.ledger.people.map((p) => p.name),
        ['Masoud', 'Ali', 'Nima']);
  });

  test('update with old 1.0.181 local data still on device: server wins',
      () async {
    freshInstall({
      PwoStore.prefsKey:
          '{"v":2,"tags":["seed_1405_v1"],"people":[{"id":"p0","name":"M"},{"id":"p1","name":"A"},{"id":"p2","name":"N"}],"months":[{"y":1405,"m":1,"a":{"p0":1}}]}',
    });
    final s = serverWith9Months();
    await PwoStore.instance.bindAccount(await remoteFor(s), '0912');
    expectIntact(s, 3);
    expect(s.es.firstWhere((e) => e['month'] == 1)['amount'], 1000000);
  });

  test('later start in local/offline mode shows the account cache, not the seed',
      () async {
    freshInstall();
    final s = serverWith9Months();
    await PwoStore.instance.bindAccount(await remoteFor(s), '0912');
    // App restarts; server unreachable -> AppState falls back to local mode.
    PwoStore.instance.debugReset();
    await PwoStore.instance.load();
    final l = PwoStore.instance.ledger;
    expect(l.monthsOf(1405).length, 9);
    expect(l.yearTotal(1405), s.es.fold<double>(0, (a, e) => a + (e['amount'] as num)));
    // Writes never go to a device-only copy: they wait in the account queue.
    await expectLater(
        PwoStore.instance.setTarget(5e8), throwsA(isA<WriteQueuedException>()));
    expect(l.target, 100000000);
    expect(PwoStore.instance.queue.items.single.account, '0912');
  });

  test('first ever sign-in on an empty server still imports device data once',
      () async {
    freshInstall();
    final s = FakePwoServer();
    await PwoStore.instance.bindAccount(await remoteFor(s), '0912');
    expect(s.calls.where((c) => c == 'POST /import').length, 1);
    expect(s.es.length, 18);
  });
}

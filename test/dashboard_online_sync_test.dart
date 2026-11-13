import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:invest/config/app_config.dart';
import 'package:invest/data/invest_api_client.dart';
import 'package:invest/data/remote_invest_service.dart';
import 'package:invest/data/session_store.dart';
import 'package:invest/domain/models/app_settings.dart';
import 'package:invest/domain/models/bank_check.dart';
import 'package:invest/domain/models/check_payment.dart';
import 'package:invest/domain/services/connection_status.dart';
import 'package:invest/state/app_state.dart';
import 'package:invest/ui/widgets/header_status.dart';
import 'package:shared_preferences/shared_preferences.dart';

BankCheck _cheque({List<CheckPayment> payments = const []}) => BankCheck(
      id: 7,
      direction: checkDirectionReceivable,
      amount: 1000,
      issueDate: '2026-10-01',
      dueDate: '2026-10-20',
      checkNumber: '101',
      bankName: 'ملت',
      counterparty: 'علی',
      kind: checkKindDeposit,
      payments: payments,
      createdAt: '2026-10-01T00:00:00',
      updatedAt: '2026-10-01T00:00:00',
    );

Map<String, Object?> _echo(Map<String, Object?> sent, {required bool storeFields}) {
  final item = Map<String, Object?>.from(sent);
  item['id'] = 7;
  if (!storeFields) {
    item.remove('kind');
    item.remove('payments');
  }
  return item;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({
      AppConfig.prefBaseUrl: 'https://vinor.test',
      AppConfig.prefSessionCookie: 'vinor_session=t',
    });
  });

  Future<AppState> online(
    Future<http.Response> Function(http.Request) handle,
  ) async {
    final session = await SessionStore.load();
    final api = InvestApiClient(session, client: MockClient(handle))
      ..restoreSessionCookie();
    return AppState()
      ..loading = false
      ..authenticated = true
      ..useRemote = true
      ..offline = false
      ..readOnlyOffline = false
      ..userPhone = '09120000000'
      ..remote = RemoteInvestService(api)
      ..settings = AppSettings(
        calendar: AppConfig.calendarJalali,
        notificationsEnabled: false,
      )
      ..checks = [_cheque()];
  }

  test('online dashboard cheque edit is not marked offline and uploads', () async {
    final bodies = <String>[];
    final state = await online((request) async {
      if (request.method == 'PATCH' && request.url.path.endsWith('/checks/7')) {
        bodies.add(request.body);
        final sent = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({
            'success': true,
            'item': _echo(sent.cast<String, Object?>(), storeFields: true),
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response(
        jsonEncode({'success': true, 'items': []}),
        200,
        headers: {'content-type': 'application/json'},
      );
    });

    final payment = CheckPayment(
      checkId: 7,
      amount: 250,
      paidAt: '2026-10-06',
      note: 'قسط',
    );
    final result = await state.saveCheck(
      _cheque(payments: [payment]),
    );

    expect(state.offline, isFalse);
    expect(state.checksAwaitingServer, isFalse);
    expect(result.synced, isTrue);
    expect(result.check.kind, checkKindDeposit);
    expect(result.check.payments.single.amount, 250);
    expect(bodies, hasLength(1));
    final sent = jsonDecode(bodies.single) as Map<String, dynamic>;
    expect(sent['kind'], 'deposit');
    expect((sent['payments'] as List).single['amount'], 250);
    expect(state.connectionStatus.isOnline, isTrue);
    state.dispose();
  });

  test('a failed upload stays queued while the user stays online', () async {
    final state = await online((request) async {
      if (request.method == 'PATCH') {
        return http.Response(
          jsonEncode({
            'success': false,
            'error': 'validation',
            'message': 'شماره چک یا شناسه صیادی را وارد کنید.',
          }),
          400,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response(
        jsonEncode({'success': true, 'items': []}),
        200,
        headers: {'content-type': 'application/json'},
      );
    });

    await expectLater(
      state.saveCheck(_cheque()),
      throwsA(isA<InvestApiException>()),
    );
    expect(state.offline, isFalse);
    expect(state.checksAwaitingServer, isFalse);
    expect(state.checkSyncError, contains('صیادی'));
    state.dispose();
  });

  test('a queued upload while online is labeled connected and names the error', () async {
    final state = await online((request) async {
      if (request.method == 'PATCH') {
        return http.Response('down', 503, headers: {'content-type': 'text/plain'});
      }
      return http.Response(
        jsonEncode({'success': true, 'items': []}),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    addTearDown(state.dispose);

    final saved = await state.saveCheck(_cheque());
    expect(saved.synced, isFalse);
    expect(state.offline, isFalse);
    expect(state.connectionStatus, AppConnectionStatus.connected);
    expect(state.checksAwaitingServer, isTrue);
    final status = HeaderStatus.of(
      conn: state.connectionStatus,
      pending: state.pendingWrites,
    );
    expect(status.text.startsWith('متصل'), isTrue);
    expect(status.text.contains('آفلاین'), isFalse);
    expect(status.text.contains('در صف'), isTrue);
    expect(state.checkSyncError, isNotNull);
  });
}

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:invest/config/app_config.dart';
import 'package:invest/data/invest_api_client.dart';
import 'package:invest/data/remote_invest_service.dart';
import 'package:invest/data/session_store.dart';
import 'package:invest/domain/models/bank_check.dart';
import 'package:invest/ui/widgets/user_error.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<RemoteInvestService> service(MockClient client) async {
    SharedPreferences.setMockInitialValues({
      AppConfig.prefBaseUrl: 'https://vinor.ir',
      AppConfig.prefSessionCookie: 'vinor_session=session-token',
    });
    final session = await SessionStore.load();
    final api = InvestApiClient(session, client: client);
    api.restoreSessionCookie();
    return RemoteInvestService(api);
  }

  Map<String, Object?> chequeJson({int id = 7}) => {
        'id': id,
        'direction': 'receivable',
        'direction_label': 'دریافتی',
        'amount': 1500000,
        'issue_date': '2026-10-01',
        'due_date': '2026-10-20',
        'check_number': '101',
        'sayad_id': '1234567890123456',
        'bank_name': 'ملت',
        'branch': '',
        'counterparty': 'رضا',
        'purpose': '',
        'note': '',
        'status': 'pending',
        'status_label': 'نزد صندوق',
        'settled_date': null,
        'is_open': true,
        'days_until_due': 3,
        'due_label': '۳ روز تا سررسید',
        'created_at': '2026-10-01T00:00:00',
        'updated_at': '2026-10-01T00:00:00',
      };

  test('sends the session cookie and the same value as a bearer token', () async {
    late http.Request seen;
    final remote = await service(MockClient((request) async {
      seen = request;
      return http.Response(
        jsonEncode({
          'success': true,
          'items': [chequeJson()],
          'summary': {},
          'count': 1,
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    }));

    final items = await remote.listChecks();
    expect(seen.headers['cookie'], 'vinor_session=session-token');
    expect(seen.headers['authorization'], 'Bearer session-token');
    expect(seen.url.path, '/invest/api/v1/checks');
    expect(items, isNotNull);
    expect(items!.single.statusLabel, 'نزد صندوق');
    expect(items.single.amount, 1500000);
  });

  test('missing checks route is an empty capability, not an error', () async {
    final remote = await service(MockClient((request) async {
      return http.Response(
        jsonEncode({
          'success': false,
          'error': 'not_found',
          'message': 'Not Found',
        }),
        404,
        headers: {'content-type': 'application/json'},
      );
    }));
    expect(await remote.listChecks(), isNull);
  });

  test('create keeps the client id and surfaces a Persian conflict', () async {
    final calls = <String>[];
    var posts = 0;
    final remote = await service(MockClient((request) async {
      calls.add('${request.method} ${request.url.path}');
      if (request.method == 'POST' && request.url.path.endsWith('/checks')) {
        posts += 1;
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['id'], 42);
        expect(body['sayad_id'], '1234567890123456');
        if (posts == 1) {
          return http.Response(
            jsonEncode({'success': true, 'item': chequeJson(id: 42)}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response(
          jsonEncode({
            'success': false,
            'error': 'conflict',
            'message': 'این شناسه صیادی قبلاً ثبت شده است.',
          }),
          409,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response(
        jsonEncode({
          'success': false,
          'error': 'conflict',
          'message': 'این شناسه صیادی قبلاً ثبت شده است.',
        }),
        409,
        headers: {'content-type': 'application/json'},
      );
    }));

    final created = await remote.createCheck(
      BankCheck(
        id: 42,
        direction: checkDirectionReceivable,
        amount: 1500000,
        issueDate: '2026-10-01',
        dueDate: '2026-10-20',
        sayadId: '1234567890123456',
        status: checkStatusPending,
      ),
    );
    expect(created.id, 42);
    expect(created.statusLabel, 'نزد صندوق');

    InvestApiException? conflict;
    try {
      await remote.createCheck(created);
    } on InvestApiException catch (e) {
      conflict = e;
    }
    expect(conflict, isNotNull);
    expect(conflict!.statusCode, 409);
    expect(
      formatUserError(conflict),
      'این شناسه صیادی قبلاً ثبت شده است.',
    );
    expect(calls, ['POST /invest/api/v1/checks', 'POST /invest/api/v1/checks']);
  });

  test('delete falls back to POST and reminders keep bounced rows', () async {
    final remote = await service(MockClient((request) async {
      if (request.method == 'DELETE') {
        return http.Response(
          jsonEncode({
            'success': false,
            'error': 'not_found',
            'message': 'Not Found',
          }),
          404,
          headers: {'content-type': 'application/json'},
        );
      }
      if (request.url.path.endsWith('/delete')) {
        return http.Response(
          jsonEncode({'success': true, 'deleted': true, 'id': 7}),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response(
        jsonEncode({
          'success': true,
          'within_days': 7,
          'overdue': [chequeJson(id: 1)],
          'due_soon': [chequeJson(id: 2)],
          'bounced': [
            {
              ...chequeJson(id: 3),
              'status': 'bounced',
              'status_label': 'برگشتی',
            },
          ],
          'items': [chequeJson(id: 1), chequeJson(id: 2)],
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    }));

    await remote.deleteCheck(7);
    final reminders = await remote.fetchCheckReminders(withinDays: 7);
    expect(reminders, isNotNull);
    expect(reminders!.overdue.single.id, 1);
    expect(reminders.dueSoon.single.id, 2);
    expect(reminders.bounced.single.statusLabel, 'برگشتی');
  });

  test('a missing cheque stays a Persian 404', () async {
    final remote = await service(MockClient((request) async {
      return http.Response(
        jsonEncode({
          'success': false,
          'error': 'not_found',
          'message': 'این چک پیدا نشد.',
        }),
        404,
        headers: {'content-type': 'application/json'},
      );
    }));
    expect(
      () => remote.deleteCheck(9),
      throwsA(
        isA<InvestApiException>().having(
          (e) => e.message,
          'message',
          'این چک پیدا نشد.',
        ),
      ),
    );
  });
}

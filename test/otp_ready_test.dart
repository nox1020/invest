import 'dart:async';
import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:invest/config/app_config.dart';
import 'package:invest/data/invest_api_client.dart';
import 'package:invest/data/session_store.dart';
import 'package:invest/state/app_state.dart';
import 'package:invest/ui/pages/login_page.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('blank or mistyped server URL still points at Vinor', () async {
    SharedPreferences.setMockInitialValues({
      AppConfig.prefBaseUrl: '',
    });
    expect((await SessionStore.load()).baseUrl, AppConfig.defaultBaseUrl);

    SharedPreferences.setMockInitialValues({
      AppConfig.prefBaseUrl: 12,
    });
    expect((await SessionStore.load()).baseUrl, AppConfig.defaultBaseUrl);

    SharedPreferences.setMockInitialValues({
      AppConfig.prefBaseUrl: 'https://vinor.ir/',
    });
    expect((await SessionStore.load()).baseUrl, 'https://vinor.ir/');
  });

  test('OTP is requested even when startup never created the client', () async {
    SharedPreferences.setMockInitialValues({});
    late http.Request seen;
    final state = AppState(
      httpClient: MockClient((request) async {
        seen = request;
        return http.Response(
          jsonEncode({
            'success': true,
            'message': 'کد تأیید ارسال شد.',
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );

    final debug = await state.requestOtp('۰۹۱۲۱۲۳۴۵۶۷');
    expect(debug, isNull);
    expect(seen.method, 'POST');
    expect(seen.url.toString(), 'https://vinor.ir/auth/request-otp');
    expect(jsonDecode(seen.body), {'phone': '۰۹۱۲۱۲۳۴۵۶۷'});
    expect(state.error, isNot('API آماده نیست'));
  });

  test('requestOtp waits 20 seconds so a slow sms.ir reply still succeeds', () {
    fakeAsync((async) {
      SharedPreferences.setMockInitialValues({});
      InvestApiClient? api;
      SessionStore.load().then((session) {
        api = InvestApiClient(
          session,
          timeout: const Duration(seconds: 10),
          client: MockClient((request) {
            return Future<http.Response>.delayed(
              const Duration(seconds: 12),
              () => http.Response(
                jsonEncode({'success': true, 'debug_code': '12121'}),
                200,
                headers: {'content-type': 'application/json'},
              ),
            );
          }),
        );
      });
      async.flushMicrotasks();

      String? code;
      Object? failure;
      api!.requestOtp('09121234567').then((value) {
        code = value;
      }, onError: (Object error) {
        failure = error;
      });

      async.elapse(const Duration(seconds: 10));
      expect(failure, isNull, reason: 'default 10s timeout must not cancel OTP');
      expect(code, isNull);

      async.elapse(const Duration(seconds: 2));
      async.flushMicrotasks();
      expect(failure, isNull);
      expect(code, '12121');
    });
  });

  testWidgets('the code button stays disabled while OTP is in flight',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final gate = Completer<http.Response>();
    final state = AppState(
      httpClient: MockClient((request) => gate.future),
    );

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: state,
        child: const MaterialApp(home: LoginPage()),
      ),
    );
    await tester.enterText(find.byType(TextField), '09121234567');
    await tester.tap(find.text('دریافت کد'));
    await tester.pump();

    expect(find.text('لطفاً صبر کنید…'), findsOneWidget);
    expect(tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed,
        isNull);

    gate.complete(
      http.Response(
        jsonEncode({'success': true}),
        200,
        headers: {'content-type': 'application/json'},
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('ورود'), findsOneWidget);
  });
}

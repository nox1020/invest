import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:invest/config/app_config.dart';
import 'package:invest/data/session_store.dart';
import 'package:invest/state/app_state.dart';
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
}

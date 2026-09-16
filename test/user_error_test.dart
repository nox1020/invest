import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:invest/data/invest_api_client.dart';
import 'package:invest/ui/widgets/user_error.dart';

void main() {
  test('keeps Persian ArgumentError messages', () {
    expect(
      formatUserError(ArgumentError('نام دارایی الزامی است.')),
      'نام دارایی الزامی است.',
    );
  });

  test('hides NoSuchMethodError from APK users', () {
    const raw =
        "NoSuchMethodError: Class 'RemoteInvestService' has no instance method 'createAsset'\n"
        "Receiver: Instance of 'RemoteInvestService'\n"
        "Tried calling: createAsset(buyDate: \"2026-09-16\")";
    expect(
      formatUserError(Exception(raw)),
      'این عملیات در نسخه فعلی پشتیبانی نمی‌شود. برنامه را به‌روز کنید.',
    );
  });

  test('maps network API errors', () {
    expect(
      formatUserError(
        InvestApiException(
          'ارتباط با سرور برقرار نشد (آفلاین).',
          errorCode: 'network_error',
        ),
      ),
      'ارتباط با سرور برقرار نشد (آفلاین).',
    );
    expect(
      formatUserError(TimeoutException('timed out')),
      'زمان اتصال به سرور تمام شد. دوباره تلاش کنید.',
    );
  });

  test('maps HTTP status when API message is technical', () {
    expect(
      formatUserError(
        InvestApiException('Internal Server Error', statusCode: 500),
      ),
      'سرور موقتاً در دسترس نیست. کمی بعد تلاش کنید.',
    );
  });
}

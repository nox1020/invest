import 'dart:async';

import 'package:flutter/services.dart';
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
    final message = formatUserError(Exception(raw));
    expect(message, 'به‌روزرسانی انجام نشد. دوباره تلاش کنید.');
    expect(message, isNot(contains('به‌روز کنید')));
    expect(message, isNot(contains('برنامه را')));
    expect(
      formatUserError(Exception("TypeError: type 'String' is not a subtype of type 'int'")),
      'به‌روزرسانی انجام نشد. دوباره تلاش کنید.',
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

  test('names the platform channel code and message', () {
    expect(
      refreshFailureCode(
        PlatformException(
          code: 'channel-error',
          message: 'TransactionTooLargeException: data parcel size',
        ),
      ),
      'PlatformException/channel-error: TransactionTooLargeException: data parcel size',
    );
    expect(
      refreshFailureCode(PlatformException(code: 'sqlite_error')),
      'PlatformException/sqlite_error',
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

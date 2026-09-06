import 'package:flutter_test/flutter_test.dart';
import 'package:invest/domain/utils/sms_otp.dart';

void main() {
  test('extracts Vinor SMS Retriever sample OTP', () {
    const sms = '''
<#> 94300
@vinor.ir #94300
4R707/AKLt0
''';
    expect(SmsOtp.extract(sms), '94300');
  });

  test('extracts hash-tagged OTP', () {
    expect(SmsOtp.extract('@vinor.ir #12345'), '12345');
  });

  test('extracts <#>-prefixed OTP', () {
    expect(SmsOtp.extract('<#> 67890\nsuffix'), '67890');
  });

  test('returns null for empty', () {
    expect(SmsOtp.extract(null), isNull);
    expect(SmsOtp.extract(''), isNull);
    expect(SmsOtp.extract('   '), isNull);
  });
}

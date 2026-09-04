import 'package:flutter_test/flutter_test.dart';
import 'package:invest/data/invest_api_client.dart';

void main() {
  test('AuthCheckResult flags', () {
    expect(
      const AuthCheckResult(AuthCheckStatus.authenticated).isAuthenticated,
      isTrue,
    );
    expect(
      const AuthCheckResult(AuthCheckStatus.offline).isAuthenticated,
      isTrue,
    );
    expect(
      const AuthCheckResult(AuthCheckStatus.offline).isOffline,
      isTrue,
    );
    expect(
      const AuthCheckResult(AuthCheckStatus.unauthenticated).isAuthenticated,
      isFalse,
    );
  });
}

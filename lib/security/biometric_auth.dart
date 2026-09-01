import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:local_auth_android/local_auth_android.dart';

/// Fingerprint / face unlock for the local app lock (not Vinor OTP).
class BiometricAuth {
  BiometricAuth._();

  static final LocalAuthentication _auth = LocalAuthentication();

  static const _androidMessages = AndroidAuthMessages(
    signInTitle: 'احراز هویت V+',
    biometricHint: 'اثر انگشت یا چهره',
    biometricNotRecognized: 'شناسایی نشد. دوباره تلاش کنید.',
    biometricRequiredTitle: 'ورود بیومتریک',
    biometricSuccess: 'تأیید شد',
    cancelButton: 'انصراف',
    deviceCredentialsRequiredTitle: 'رمز دستگاه',
    deviceCredentialsSetupDescription: 'رمز صفحه‌قفل گوشی را تنظیم کنید',
    goToSettingsButton: 'تنظیمات',
    goToSettingsDescription:
        'برای استفاده از بیومتریک، آن را در تنظیمات گوشی فعال کنید.',
  );

  static Future<bool> isDeviceSupported() async {
    if (kIsWeb) return false;
    try {
      return await _auth.isDeviceSupported();
    } catch (_) {
      return false;
    }
  }

  static Future<bool> hasEnrolledBiometrics() async {
    if (kIsWeb) return false;
    try {
      if (!await _auth.canCheckBiometrics) return false;
      final types = await _auth.getAvailableBiometrics();
      return types.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> isAvailable() async {
    if (!await isDeviceSupported()) return false;
    return hasEnrolledBiometrics();
  }

  static Future<List<BiometricType>> availableTypes() async {
    try {
      return await _auth.getAvailableBiometrics();
    } catch (_) {
      return const [];
    }
  }

  static String labelForTypes(List<BiometricType> types) {
    if (types.contains(BiometricType.face)) {
      return 'تشخیص چهره';
    }
    if (types.contains(BiometricType.fingerprint)) {
      return 'اثر انگشت';
    }
    if (types.contains(BiometricType.strong) ||
        types.contains(BiometricType.weak)) {
      return 'بیومتریک';
    }
    return 'احراز هویت دستگاه';
  }

  static Future<BiometricAuthResult> authenticate({
    required String reason,
    bool biometricOnly = false,
  }) async {
    if (kIsWeb) {
      return const BiometricAuthResult(
        success: false,
        message: 'بیومتریک در وب پشتیبانی نمی‌شود.',
      );
    }
    try {
      final ok = await _auth.authenticate(
        localizedReason: reason,
        authMessages: const [_androidMessages],
        options: AuthenticationOptions(
          biometricOnly: biometricOnly,
          stickyAuth: true,
          sensitiveTransaction: true,
          useErrorDialogs: true,
        ),
      );
      if (ok) {
        return const BiometricAuthResult(success: true);
      }
      return const BiometricAuthResult(
        success: false,
        message: 'احراز هویت انجام نشد.',
      );
    } on PlatformException catch (e) {
      return BiometricAuthResult(
        success: false,
        message: _messageForCode(e.code, e.message),
      );
    } catch (e) {
      return BiometricAuthResult(success: false, message: e.toString());
    }
  }

  static String _messageForCode(String code, String? fallback) {
    switch (code) {
      case 'NotAvailable':
        return 'بیومتریک روی این دستگاه در دسترس نیست.';
      case 'NotEnrolled':
        return 'اثر انگشت یا چهره در تنظیمات گوشی ثبت نشده است.';
      case 'LockedOut':
        return 'تعداد تلاش‌ها زیاد بود. کمی بعد دوباره امتحان کنید.';
      case 'PermanentlyLockedOut':
        return 'بیومتریک قفل شد. با رمز صفحه‌قفل گوشی وارد شوید.';
      case 'PasscodeNotSet':
        return 'ابتدا رمز یا الگوی صفحه‌قفل گوشی را تنظیم کنید.';
      case 'OtherOperatingSystem':
        return fallback ?? 'خطای سیستم‌عامل.';
      default:
        return fallback ?? 'احراز هویت ناموفق بود.';
    }
  }
}

class BiometricAuthResult {
  const BiometricAuthResult({required this.success, this.message});

  final bool success;
  final String? message;
}

import 'package:flutter/foundation.dart';
import 'package:local_auth/local_auth.dart';

/// Fingerprint / face unlock for the local app lock (not Vinor OTP).
class BiometricAuth {
  BiometricAuth._();

  static final LocalAuthentication _auth = LocalAuthentication();

  static Future<bool> isAvailable() async {
    if (kIsWeb) return false;
    try {
      final supported = await _auth.isDeviceSupported();
      if (!supported) return false;
      final types = await _auth.getAvailableBiometrics();
      return types.isNotEmpty;
    } catch (_) {
      return false;
    }
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

  static Future<bool> authenticate({
    required String reason,
    bool biometricOnly = true,
  }) async {
    if (kIsWeb) return false;
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        options: AuthenticationOptions(
          biometricOnly: biometricOnly,
          stickyAuth: true,
          sensitiveTransaction: true,
        ),
      );
    } catch (_) {
      return false;
    }
  }
}

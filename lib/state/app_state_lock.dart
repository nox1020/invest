part of 'app_state.dart';

// Split out of app_state.dart (pure move, no behaviour change).
extension AppStateLock on AppState {
  Future<bool> unlockApp(String password) async {
    if (!appLockEnabled) {
      appUnlocked = true;
      notifyListeners();
      return true;
    }
    if (verifyAppLockPassword(password, appLockHash!)) {
      appUnlocked = true;
      notifyListeners();
      return true;
    }
    return false;
  }

  Future<void> refreshBiometricCapability() async {
    try {
      biometricDeviceSupported = await BiometricAuth.isDeviceSupported();
      biometricAvailable = await BiometricAuth.hasEnrolledBiometrics();
      if (biometricDeviceSupported) {
        biometricLabel =
            BiometricAuth.labelForTypes(await BiometricAuth.availableTypes());
      }
      notifyListeners();
    } catch (e, st) {
      logLocalFailure('biometric', e, st);
    }
  }

  Future<bool> unlockWithBiometric() async {
    if (!appLockEnabled || !biometricUnlockEnabled || !biometricAvailable) {
      return false;
    }
    final result = await BiometricAuth.authenticate(
      reason: 'برای باز کردن V+ احراز هویت کنید',
      biometricOnly: true,
    );
    if (result.success) {
      appUnlocked = true;
      notifyListeners();
      return true;
    }
    return false;
  }

  /// Returns an error message on failure, or null on success.
  Future<String?> setBiometricUnlockEnabled(bool enabled) async {
    if (enabled) {
      if (!appLockEnabled) {
        return 'ابتدا رمز ورود برنامه را تنظیم کنید.';
      }
      await refreshBiometricCapability();
      if (!biometricDeviceSupported) {
        return 'این دستگاه از بیومتریک پشتیبانی نمی‌کند.';
      }
      if (!biometricAvailable) {
        return 'ابتدا اثر انگشت یا چهره را در تنظیمات گوشی ثبت کنید.';
      }
      final result = await BiometricAuth.authenticate(
        reason: 'برای فعال‌سازی $biometricLabel احراز هویت کنید',
        biometricOnly: false,
      );
      if (!result.success) {
        return result.message ?? 'فعال‌سازی بیومتریک انجام نشد.';
      }
      await AppLockStore.saveBiometricEnabled(true);
      biometricUnlockEnabled = true;
    } else {
      await AppLockStore.saveBiometricEnabled(false);
      biometricUnlockEnabled = false;
    }
    notifyListeners();
    await _pushUserExtrasToServer();
    return null;
  }

  Future<void> setAppLockPassword(String password) async {
    final hash = hashAppLockPassword(password);
    await AppLockStore.saveHash(hash);
    appLockHash = hash;
    appLockEnabled = true;
    appUnlocked = true;
    notifyListeners();
    await _pushUserExtrasToServer();
  }

  Future<void> removeAppLock() async {
    await AppLockStore.saveHash('');
    await AppLockStore.saveBiometricEnabled(false);
    appLockHash = null;
    appLockEnabled = false;
    biometricUnlockEnabled = false;
    appUnlocked = true;
    notifyListeners();
    await _pushUserExtrasToServer();
  }
}

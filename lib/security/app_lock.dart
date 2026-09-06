import 'dart:convert';
import 'dart:typed_data';

import 'package:invest/security/pbkdf2.dart';

const int appLockMinPasswordLen = 4;
const int appLockPbkdf2Iterations = 120000;
const int _pbkdf2KeyLength = 32;

bool isAppLockEnabled(String? storedHash) =>
    storedHash != null && storedHash.trim().isNotEmpty;

String hashAppLockPassword(String password) {
  final salt = secureRandomBytes(16);
  final digest = pbkdf2HmacSha256(
    password: utf8.encode(password),
    salt: salt,
    iterations: appLockPbkdf2Iterations,
    keyLength: _pbkdf2KeyLength,
  );
  return 'pbkdf2_sha256\$$appLockPbkdf2Iterations\$'
      '${base64Encode(salt)}\$'
      '${base64Encode(digest)}';
}

bool verifyAppLockPassword(String password, String stored) {
  if (password.isEmpty || stored.isEmpty) return false;
  final parts = stored.split('\$');
  if (parts.length != 4 || parts[0] != 'pbkdf2_sha256') return false;
  try {
    final iterations = int.parse(parts[1]);
    final salt = Uint8List.fromList(base64Decode(parts[2]));
    final expected = Uint8List.fromList(base64Decode(parts[3]));
    final actual = pbkdf2HmacSha256(
      password: utf8.encode(password),
      salt: salt,
      iterations: iterations,
      keyLength: _pbkdf2KeyLength,
    );
    return constantTimeEquals(actual, expected);
  } catch (_) {
    return false;
  }
}

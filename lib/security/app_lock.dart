import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

const int appLockMinPasswordLen = 4;
const int appLockPbkdf2Iterations = 120000;

bool isAppLockEnabled(String? storedHash) =>
    storedHash != null && storedHash.trim().isNotEmpty;

String hashAppLockPassword(String password) {
  final salt = _randomBytes(16);
  final digest = _pbkdf2(password, salt, appLockPbkdf2Iterations);
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
    final salt = base64Decode(parts[2]);
    final expected = Uint8List.fromList(base64Decode(parts[3]));
    final actual = _pbkdf2(password, salt, iterations);
    if (actual.length != expected.length) return false;
    var diff = 0;
    for (var i = 0; i < actual.length; i++) {
      diff |= actual[i] ^ expected[i];
    }
    return diff == 0;
  } catch (_) {
    return false;
  }
}

Uint8List _pbkdf2(String password, Uint8List salt, int iterations) {
  return Uint8List.fromList(
    pbkdf2(
      sha256,
      utf8.encode(password),
      salt,
      iterations,
      32,
    ),
  );
}

Uint8List _randomBytes(int length) {
  final rnd = Random.secure();
  return Uint8List.fromList(
    List<int>.generate(length, (_) => rnd.nextInt(256)),
  );
}

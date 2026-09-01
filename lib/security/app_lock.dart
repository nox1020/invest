import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

const int appLockMinPasswordLen = 4;
const int appLockPbkdf2Iterations = 120000;
const int _pbkdf2KeyLength = 32;
const int _sha256DigestLength = 32;

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
  final hmac = Hmac(sha256, utf8.encode(password));
  final blockCount =
      (_pbkdf2KeyLength + _sha256DigestLength - 1) ~/ _sha256DigestLength;
  final out = BytesBuilder();
  for (var block = 1; block <= blockCount; block++) {
    final blockIndex = ByteData(4)..setUint32(0, block, Endian.big);
    var u = hmac
        .convert([...salt, ...blockIndex.buffer.asUint8List()])
        .bytes;
    var t = List<int>.from(u);
    for (var i = 1; i < iterations; i++) {
      u = hmac.convert(u).bytes;
      for (var j = 0; j < t.length; j++) {
        t[j] ^= u[j];
      }
    }
    out.add(t);
  }
  return Uint8List.fromList(out.takeBytes().sublist(0, _pbkdf2KeyLength));
}

Uint8List _randomBytes(int length) {
  final rnd = Random.secure();
  return Uint8List.fromList(
    List<int>.generate(length, (_) => rnd.nextInt(256)),
  );
}

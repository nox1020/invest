import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

const int pbkdf2Sha256DigestLength = 32;

/// PBKDF2-HMAC-SHA256 key derivation (shared by app lock + backup crypto).
Uint8List pbkdf2HmacSha256({
  required List<int> password,
  required Uint8List salt,
  required int iterations,
  required int keyLength,
}) {
  final hmac = Hmac(sha256, password);
  final blockCount =
      (keyLength + pbkdf2Sha256DigestLength - 1) ~/ pbkdf2Sha256DigestLength;
  final out = BytesBuilder(copy: false);
  for (var block = 1; block <= blockCount; block++) {
    final blockIndex = ByteData(4)..setUint32(0, block, Endian.big);
    var u = hmac.convert([...salt, ...blockIndex.buffer.asUint8List()]).bytes;
    var t = List<int>.from(u);
    for (var i = 1; i < iterations; i++) {
      u = hmac.convert(u).bytes;
      for (var j = 0; j < t.length; j++) {
        t[j] ^= u[j];
      }
    }
    out.add(t);
  }
  return Uint8List.fromList(out.takeBytes().sublist(0, keyLength));
}

Uint8List secureRandomBytes(int length) {
  final rnd = Random.secure();
  return Uint8List.fromList(
    List<int>.generate(length, (_) => rnd.nextInt(256)),
  );
}

bool constantTimeEquals(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a[i] ^ b[i];
  }
  return diff == 0;
}

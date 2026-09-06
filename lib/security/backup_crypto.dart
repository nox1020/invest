import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:invest/config/app_config.dart';
import 'package:invest/security/pbkdf2.dart';

/// Encrypted V+ backup container — decryptable only by this application.
///
/// Binary layout (v1):
///   magic(8) | version(1) | kdf_iters(u32 BE) | salt(16) | nonce(16)
///   | cipher_len(u32 BE) | ciphertext | mac(32)
///
/// Keystream = HMAC-SHA256(encKey, nonce || counter) XOR plaintext
/// then HMAC-SHA256 (encrypt-then-MAC) over the header and ciphertext.
/// Keys come from PBKDF2 over an app-bound secret.
class BackupCrypto {
  BackupCrypto._();

  static const magic = [0x56, 0x50, 0x4C, 0x55, 0x53, 0x42, 0x41, 0x4B]; // VPLUSBAK
  static const version = 1;
  static const saltLen = 16;
  static const nonceLen = 16;
  static const macLen = 32;
  static const keyLen = 32;
  static const defaultKdfIterations = 180000;

  /// Obfuscated material mixed with [AppConfig.applicationId].
  static List<int> get _appSecretMaterial {
    const a = 'v+·nox·2026·';
    const b = 'invest·bak·';
    const c = 'k9f2Qm7xLp';
    return utf8.encode('$a$b$c|${AppConfig.applicationId}|${AppConfig.appName}');
  }

  static Uint8List encryptUtf8(String plaintext, {int? iterations}) {
    final iters = iterations ?? defaultKdfIterations;
    final salt = secureRandomBytes(saltLen);
    final nonce = secureRandomBytes(nonceLen);
    final keys = _deriveKeys(salt, iters);
    final cipher = _xorKeystream(keys.enc, nonce, utf8.encode(plaintext));
    final header = BytesBuilder(copy: false)
      ..add(magic)
      ..addByte(version)
      ..add(_u32be(iters))
      ..add(salt)
      ..add(nonce)
      ..add(_u32be(cipher.length))
      ..add(cipher);
    final body = Uint8List.fromList(header.takeBytes());
    final mac = Hmac(sha256, keys.mac).convert(body).bytes;
    return Uint8List.fromList([...body, ...mac]);
  }

  static String decryptToUtf8(Uint8List blob) {
    if (blob.length < 8 + 1 + 4 + saltLen + nonceLen + 4 + macLen) {
      throw const BackupCryptoException('فایل پشتیبان ناقص یا آسیب‌دیده است.');
    }
    for (var i = 0; i < magic.length; i++) {
      if (blob[i] != magic[i]) {
        throw const BackupCryptoException(
          'این فایل پشتیبان V+ نیست یا رمزگشایی ممکن نیست.',
        );
      }
    }
    final ver = blob[8];
    if (ver != version) {
      throw BackupCryptoException('نسخه پشتیبان پشتیبانی نمی‌شود ($ver).');
    }
    var o = 9;
    final iters = _readU32be(blob, o);
    o += 4;
    if (iters < 10000 || iters > 5000000) {
      throw const BackupCryptoException('پارامترهای رمزنگاری نامعتبر است.');
    }
    final salt = blob.sublist(o, o + saltLen);
    o += saltLen;
    final nonce = blob.sublist(o, o + nonceLen);
    o += nonceLen;
    final cipherLen = _readU32be(blob, o);
    o += 4;
    if (cipherLen <= 0 || o + cipherLen + macLen != blob.length) {
      throw const BackupCryptoException('طول داده رمزشده نامعتبر است.');
    }
    final cipher = blob.sublist(o, o + cipherLen);
    o += cipherLen;
    final mac = blob.sublist(o, o + macLen);
    final keys = _deriveKeys(Uint8List.fromList(salt), iters);
    final body = blob.sublist(0, blob.length - macLen);
    final expected = Hmac(sha256, keys.mac).convert(body).bytes;
    if (!constantTimeEquals(
      Uint8List.fromList(expected),
      Uint8List.fromList(mac),
    )) {
      throw const BackupCryptoException(
        'یکپارچگی فایل تأیید نشد — فایل تغییر کرده یا برای این اپ نیست.',
      );
    }
    try {
      final plain = _xorKeystream(
        keys.enc,
        Uint8List.fromList(nonce),
        cipher,
      );
      return utf8.decode(plain);
    } catch (_) {
      throw const BackupCryptoException('رمزگشایی ناموفق بود.');
    }
  }

  static ({Uint8List enc, Uint8List mac}) _deriveKeys(
    Uint8List salt,
    int iterations,
  ) {
    final material = pbkdf2HmacSha256(
      password: _appSecretMaterial,
      salt: salt,
      iterations: iterations,
      keyLength: keyLen * 2,
    );
    return (
      enc: material.sublist(0, keyLen),
      mac: material.sublist(keyLen, keyLen * 2),
    );
  }

  static Uint8List _xorKeystream(
    Uint8List key,
    Uint8List nonce,
    List<int> data,
  ) {
    final out = Uint8List(data.length);
    var offset = 0;
    var counter = 0;
    final hmac = Hmac(sha256, key);
    while (offset < data.length) {
      final block = hmac.convert([...nonce, ..._u32be(counter)]).bytes;
      final n = min(block.length, data.length - offset);
      for (var i = 0; i < n; i++) {
        out[offset + i] = data[offset + i] ^ block[i];
      }
      offset += n;
      counter++;
    }
    return out;
  }

  static Uint8List _u32be(int v) {
    final b = ByteData(4)..setUint32(0, v, Endian.big);
    return b.buffer.asUint8List();
  }

  static int _readU32be(Uint8List b, int offset) =>
      ByteData.sublistView(b, offset, offset + 4).getUint32(0, Endian.big);
}

class BackupCryptoException implements Exception {
  const BackupCryptoException(this.message);
  final String message;
  @override
  String toString() => message;
}

import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:invest/config/app_config.dart';
import 'package:invest/security/pbkdf2.dart';
import 'package:pointycastle/export.dart';

/// Encrypted V+ backup container — decryptable only by this application.
///
/// Binary layout (v1):
///   magic(8) | version(1) | kdf_iters(u32 BE) | salt(16) | iv(16)
///   | cipher_len(u32 BE) | ciphertext | mac(32)
///
/// AES-256-CBC + PKCS7, then HMAC-SHA256 (encrypt-then-MAC) over the header
/// and ciphertext. Keys come from PBKDF2 over an app-bound secret.
class BackupCrypto {
  BackupCrypto._();

  static const magic = [0x56, 0x50, 0x4C, 0x55, 0x53, 0x42, 0x41, 0x4B]; // VPLUSBAK
  static const version = 1;
  static const saltLen = 16;
  static const ivLen = 16;
  static const macLen = 32;
  static const keyLen = 32;
  static const defaultKdfIterations = 180000;

  /// Obfuscated material mixed with [AppConfig.applicationId].
  /// Not user-facing; casual tools cannot open the file without the app.
  static List<int> get _appSecretMaterial {
    // Split so a simple strings dump of the APK is less obvious.
    const a = 'v+·nox·2026·';
    const b = 'invest·bak·';
    const c = 'k9f2Qm7xLp';
    return utf8.encode('$a$b$c|${AppConfig.applicationId}|${AppConfig.appName}');
  }

  static Uint8List encryptUtf8(String plaintext, {int? iterations}) {
    final iters = iterations ?? defaultKdfIterations;
    final salt = secureRandomBytes(saltLen);
    final iv = secureRandomBytes(ivLen);
    final keys = _deriveKeys(salt, iters);
    final cipher = _aesCbcEncrypt(keys.aes, iv, utf8.encode(plaintext));
    final header = BytesBuilder(copy: false)
      ..add(magic)
      ..addByte(version)
      ..add(_u32be(iters))
      ..add(salt)
      ..add(iv)
      ..add(_u32be(cipher.length))
      ..add(cipher);
    final body = Uint8List.fromList(header.takeBytes());
    final mac = Hmac(sha256, keys.mac).convert(body).bytes;
    return Uint8List.fromList([...body, ...mac]);
  }

  static String decryptToUtf8(Uint8List blob) {
    if (blob.length < 8 + 1 + 4 + saltLen + ivLen + 4 + macLen) {
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
    final iv = blob.sublist(o, o + ivLen);
    o += ivLen;
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
    if (!constantTimeEquals(Uint8List.fromList(expected), Uint8List.fromList(mac))) {
      throw const BackupCryptoException(
        'یکپارچگی فایل تأیید نشد — فایل تغییر کرده یا برای این اپ نیست.',
      );
    }
    try {
      final plain = _aesCbcDecrypt(keys.aes, Uint8List.fromList(iv), cipher);
      return utf8.decode(plain);
    } catch (_) {
      throw const BackupCryptoException('رمزگشایی ناموفق بود.');
    }
  }

  static ({Uint8List aes, Uint8List mac}) _deriveKeys(
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
      aes: material.sublist(0, keyLen),
      mac: material.sublist(keyLen, keyLen * 2),
    );
  }

  static Uint8List _aesCbcEncrypt(Uint8List key, Uint8List iv, List<int> plain) {
    final padded = _pkcs7Pad(Uint8List.fromList(plain), 16);
    final cipher = CBCBlockCipher(AESEngine())
      ..init(true, ParametersWithIV(KeyParameter(key), iv));
    final out = Uint8List(padded.length);
    var offset = 0;
    while (offset < padded.length) {
      offset += cipher.processBlock(padded, offset, out, offset);
    }
    return out;
  }

  static Uint8List _aesCbcDecrypt(Uint8List key, Uint8List iv, Uint8List cipher) {
    if (cipher.length % 16 != 0) {
      throw StateError('bad cipher length');
    }
    final cbc = CBCBlockCipher(AESEngine())
      ..init(false, ParametersWithIV(KeyParameter(key), iv));
    final out = Uint8List(cipher.length);
    var offset = 0;
    while (offset < cipher.length) {
      offset += cbc.processBlock(cipher, offset, out, offset);
    }
    return _pkcs7Unpad(out, 16);
  }

  static Uint8List _pkcs7Pad(Uint8List data, int blockSize) {
    final pad = blockSize - (data.length % blockSize);
    return Uint8List.fromList([...data, ...List.filled(pad, pad)]);
  }

  static Uint8List _pkcs7Unpad(Uint8List data, int blockSize) {
    if (data.isEmpty) throw StateError('empty');
    final pad = data.last;
    if (pad < 1 || pad > blockSize || pad > data.length) {
      throw StateError('bad padding');
    }
    for (var i = data.length - pad; i < data.length; i++) {
      if (data[i] != pad) throw StateError('bad padding');
    }
    return data.sublist(0, data.length - pad);
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

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:invest/config/app_config.dart';
import 'package:invest/domain/models/app_settings.dart';
import 'package:invest/domain/models/asset.dart';
import 'package:invest/domain/models/trade.dart';
import 'package:invest/domain/models/withdrawal.dart';
import 'package:invest/domain/services/backup_service.dart';
import 'package:invest/security/backup_crypto.dart';
import 'package:invest/security/pbkdf2.dart';

void main() {
  test('backup crypto round-trip is authenticated', () {
    const plain = '{"hello":"world","n":42}';
    final enc = BackupCrypto.encryptUtf8(plain, iterations: 12000);
    expect(enc.sublist(0, 8), BackupCrypto.magic);
    expect(BackupCrypto.decryptToUtf8(enc), plain);

    final tampered = Uint8List.fromList(enc);
    tampered[tampered.length - 1] ^= 0xff;
    expect(
      () => BackupCrypto.decryptToUtf8(tampered),
      throwsA(isA<BackupCryptoException>()),
    );
  });

  test('foreign or truncated blobs are rejected', () {
    expect(
      () => BackupCrypto.decryptToUtf8(Uint8List.fromList([1, 2, 3])),
      throwsA(isA<BackupCryptoException>()),
    );
    final junk = utf8.encode('not-a-backup');
    expect(
      () => BackupCrypto.decryptToUtf8(Uint8List.fromList(junk)),
      throwsA(isA<BackupCryptoException>()),
    );
  });

  test('full payload encode/decode preserves all entities', () {
    final payload = BackupService.buildFromMemory(
      settings: AppSettings(
        calendar: AppConfig.calendarJalali,
        currency: AppConfig.currencyToman,
        theme: AppConfig.themeDark,
        livePricesEnabled: true,
        usdtApiEnabled: false,
        goldApiEnabled: true,
        usdtTmnRate: 100000,
      ),
      assets: [
        Asset(
          id: 1,
          name: 'طلا',
          symbol: 'XAU',
          quantity: 2,
          avgBuyPrice: 10,
          currentPrice: 12,
          notes: '[kind:gold]',
        ),
      ],
      openTrades: [
        Trade(
          id: 10,
          assetId: 1,
          status: AppConfig.tradeOpen,
          quantity: 2,
          buyPrice: 10,
          buyFee: 1,
          buyDate: '2024-03-20',
          assetName: 'طلا',
        ),
      ],
      closedTrades: [
        Trade(
          id: 11,
          assetId: 1,
          status: AppConfig.tradeClosed,
          quantity: 1,
          buyPrice: 8,
          sellPrice: 9,
          buyDate: '2024-01-01',
          sellDate: '2024-02-01',
          realizedPnl: 1,
          assetName: 'طلا',
        ),
      ],
      withdrawals: [
        Withdrawal(id: 3, amount: 500, note: 'تست', createdAt: '2024-02-02'),
      ],
      capitalSnapshots: [
        {'id': 1, 'date': '2024-02-01', 'total_value': 100, 'created_at': 'x'},
      ],
      appLockHash: 'pbkdf2_sha256\$1\$abc\$def',
      biometricUnlockEnabled: true,
      userPhone: '0912',
      baseUrl: 'https://vinor.ir',
    );

    // Production default KDF (180000) is too heavy for unit tests; decrypt
    // rejects iterations below 10000, so use a valid low-iter path here.
    final bytes = BackupService.encode(payload, iterations: 12000);
    expect(bytes.length, greaterThan(64));
    final restored = BackupService.decode(bytes);

    expect(restored.assets.single.name, 'طلا');
    expect(restored.openTradeCount, 1);
    expect(restored.closedTradeCount, 1);
    expect(restored.withdrawals.single.amount, 500);
    // JSON round-trip may yield int or double for numbers.
    expect(
      (restored.capitalSnapshots.single['total_value'] as num).toDouble(),
      100,
    );
    expect(restored.appLockHash, 'pbkdf2_sha256\$1\$abc\$def');
    expect(restored.biometricUnlockEnabled, isTrue);
    expect(restored.settings.usdtApiEnabled, isFalse);
    expect(restored.settings.goldApiEnabled, isTrue);
    expect(restored.settings.usdtTmnRate, 100000);
    expect(restored.userPhone, '0912');
    expect(restored.baseUrl, 'https://vinor.ir');
  });

  test('pbkdf2 is deterministic', () {
    final a = pbkdf2HmacSha256(
      password: utf8.encode('pwd'),
      salt: Uint8List.fromList(List.filled(16, 7)),
      iterations: 1000,
      keyLength: 32,
    );
    final b = pbkdf2HmacSha256(
      password: utf8.encode('pwd'),
      salt: Uint8List.fromList(List.filled(16, 7)),
      iterations: 1000,
      keyLength: 32,
    );
    expect(a, b);
  });
}

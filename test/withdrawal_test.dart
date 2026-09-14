import 'package:flutter_test/flutter_test.dart';
import 'package:invest/config/app_config.dart';
import 'package:invest/domain/models/trade.dart';
import 'package:invest/domain/models/withdrawal.dart';
import 'package:invest/domain/services/withdrawal_allowance.dart';
import 'package:invest/data/app_database.dart';
import 'package:invest/data/withdrawal_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Trade _lot({
  required double qty,
  required double buyPrice,
  double buyFee = 0,
  String status = AppConfig.tradeOpen,
}) {
  return Trade(
    assetId: 1,
    status: status,
    quantity: qty,
    buyPrice: buyPrice,
    buyFee: buyFee,
  );
}

void main() {
  test('withdrawable amount is realized profit minus withdrawals', () {
    expect(
      computeWithdrawableAmount(realizedPnl: 100, withdrawnTotal: 30),
      70,
    );
    expect(
      computeWithdrawableAmount(realizedPnl: 20, withdrawnTotal: 50),
      0,
    );
    expect(
      computeWithdrawableAmount(realizedPnl: -10, withdrawnTotal: 0),
      0,
    );
  });

  group('WithdrawalAllowance', () {
    test('caps yearly withdrawals at percent of total inflows', () {
      final allowance = WithdrawalAllowance.compute(
        realizedPnl: 400000,
        openTrades: [_lot(qty: 1, buyPrice: 1000000)],
        closedTrades: [_lot(qty: 1, buyPrice: 1000000, status: AppConfig.tradeClosed)],
        withdrawals: [
          Withdrawal(amount: 50000, createdAt: '2026-04-01'),
        ],
        annualPct: 10,
        calendar: AppConfig.calendarGregorian,
        asOfIso: '2026-09-14',
      );
      expect(allowance.inflows, 2000000);
      expect(allowance.annualCap, 200000);
      expect(allowance.yearWithdrawn, 50000);
      expect(allowance.remainingAnnual, 150000);
      expect(allowance.remainingRealized, 350000);
      expect(allowance.available, 150000);
      expect(allowance.yearKey, '2026');
    });

    test('realized remaining can bind below the annual quota', () {
      final allowance = WithdrawalAllowance.compute(
        realizedPnl: 80000,
        openTrades: [_lot(qty: 1, buyPrice: 1000000)],
        closedTrades: const [],
        withdrawals: [
          Withdrawal(amount: 20000, createdAt: '2026-02-01'),
        ],
        annualPct: 10,
        calendar: AppConfig.calendarGregorian,
        asOfIso: '2026-09-14',
      );
      expect(allowance.annualCap, 100000);
      expect(allowance.remainingAnnual, 80000);
      expect(allowance.remainingRealized, 60000);
      expect(allowance.available, 60000);
    });

    test('ignores rejected and previous-year withdrawals in the annual quota',
        () {
      final allowance = WithdrawalAllowance.compute(
        realizedPnl: 500000,
        openTrades: [_lot(qty: 1, buyPrice: 1000000)],
        closedTrades: const [],
        withdrawals: [
          Withdrawal(amount: 40000, createdAt: '2025-12-01'),
          Withdrawal(
            amount: 30000,
            status: 'rejected',
            createdAt: '2026-03-01',
          ),
          Withdrawal(amount: 10000, createdAt: '2026-06-01'),
        ],
        annualPct: 10,
        calendar: AppConfig.calendarGregorian,
        asOfIso: '2026-09-14',
      );
      expect(allowance.yearWithdrawn, 10000);
      expect(allowance.withdrawnAllTime, 50000);
      expect(allowance.remainingAnnual, 90000);
      expect(allowance.remainingRealized, 450000);
      expect(allowance.available, 90000);
    });

    test('empty createdAt counts toward the current year', () {
      final allowance = WithdrawalAllowance.compute(
        realizedPnl: 200000,
        openTrades: [_lot(qty: 1, buyPrice: 500000)],
        closedTrades: const [],
        withdrawals: [Withdrawal(amount: 10000)],
        annualPct: 10,
        calendar: AppConfig.calendarGregorian,
        asOfIso: '2026-09-14',
      );
      expect(allowance.yearWithdrawn, 10000);
      expect(allowance.available, 40000);
    });

    test('uses jalali year boundaries', () {
      final allowance = WithdrawalAllowance.compute(
        realizedPnl: 300000,
        openTrades: [_lot(qty: 1, buyPrice: 1000000)],
        closedTrades: const [],
        withdrawals: [
          Withdrawal(amount: 20000, createdAt: '2025-03-20'),
          Withdrawal(amount: 15000, createdAt: '2025-03-21'),
        ],
        annualPct: 10,
        calendar: AppConfig.calendarJalali,
        asOfIso: '2025-09-14',
      );
      expect(allowance.yearKey, '1404');
      // 2025-03-20 is 1403/12/30; 2025-03-21 is 1404/01/01.
      expect(allowance.yearWithdrawn, 15000);
      expect(allowance.available, 85000);
    });
  });

  group('WithdrawalRepository', () {
    setUpAll(() {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    });

    late Database db;
    late WithdrawalRepository repo;

    setUp(() async {
      final path =
          '${inMemoryDatabasePath}_${DateTime.now().microsecondsSinceEpoch}';
      db = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 2,
          singleInstance: false,
          onCreate: (db, version) async {
            await AppDatabase.migrateFresh(db);
          },
        ),
      );
      repo = WithdrawalRepository(db);
    });

    tearDown(() async {
      await db.close();
    });

    test('stores history and sums completed amounts', () async {
      await repo.create(Withdrawal(amount: 150000, note: 'بانک'));
      await repo.create(
        Withdrawal(amount: 50000, status: 'rejected', note: 'لغو'),
      );
      await repo.create(Withdrawal(amount: 20000));

      final items = await repo.listAll();
      expect(items.length, 3);
      expect(await repo.totalCompleted(), 170000);
      expect(items.first.amount, 20000);
    });
  });
}

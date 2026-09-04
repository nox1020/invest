import 'package:flutter_test/flutter_test.dart';
import 'package:invest/data/app_database.dart';
import 'package:invest/data/withdrawal_repository.dart';
import 'package:invest/domain/models/withdrawal.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

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

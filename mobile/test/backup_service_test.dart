import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:smartledger/data/backup/backup_service.dart';
import 'package:smartledger/data/repositories/transaction_repository.dart';
import 'package:smartledger/data/sqlite/app_database.dart';
import 'package:smartledger/data/sqlite/transaction_local_data_source.dart';
import 'package:smartledger/domain/models/ledger_transaction.dart';
import 'package:smartledger/domain/models/transaction_type.dart';
import 'package:smartledger/shared/clock.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  late Directory tempDir;
  late String databasePath;
  late Database database;
  late MutableClock clock;
  late TransactionLocalDataSource dataSource;
  late TransactionRepository repository;
  late BackupService backupService;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp(
      'smart_ledger_backup_test_',
    );
    databasePath = path.join(tempDir.path, 'smart-ledger.sqlite');
    database = await AppDatabase.openAtPath(
      databasePath,
      databaseFactory: databaseFactoryFfi,
    );
    clock = MutableClock(DateTime.utc(2026, 8, 31, 10, 30));
    dataSource = TransactionLocalDataSource(database);
    repository = TransactionRepository(dataSource, clock: clock);
    backupService = BackupService(
      dataSource: dataSource,
      clock: clock,
      backupDirectoryPath: path.join(tempDir.path, 'backups'),
    );
  });

  tearDown(() async {
    await database.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('导出 JSON 包含元数据、全部交易字段和软删除记录', () async {
    final active = await repository.create(_newTransaction());
    final deleted = await repository.create(
      _newTransaction(
        amountCents: 26000,
        type: TransactionType.income,
        category: 'salary',
        note: null,
        originalText: '260工资',
      ),
    );
    clock.set(DateTime.utc(2026, 8, 31, 11));
    await repository.softDelete(deleted.id);

    final result = await backupService.exportBackup();
    final file = File(result.filePath);
    final document =
        jsonDecode(await file.readAsString()) as Map<String, dynamic>;

    expect(result.transactionCount, 2);
    expect(result.deletedCount, 1);
    expect(document['backup_version'], BackupService.backupVersion);
    expect(document['app_version'], BackupService.appVersion);
    expect(document['database_version'], 1);
    expect(DateTime.tryParse(document['created_at'] as String), isNotNull);

    final transactions = document['transactions'] as List<dynamic>;
    expect(transactions, hasLength(2));
    final fields = (transactions.first as Map<String, dynamic>).keys.toSet();
    expect(fields, {
      'id',
      'amount_cents',
      'type',
      'category',
      'note',
      'original_text',
      'transaction_date',
      'created_at',
      'updated_at',
      'deleted_at',
    });
    expect(
      transactions.map((item) => (item as Map<String, dynamic>)['id']).toSet(),
      {active.id, deleted.id},
    );
    expect(
      transactions.cast<Map<String, dynamic>>().singleWhere(
        (item) => item['id'] == deleted.id,
      )['deleted_at'],
      isNotNull,
    );
  });

  test('100 条账目删除数据库后恢复，统计和软删除状态保持一致', () async {
    final created = <LedgerTransaction>[];
    for (var index = 0; index < 100; index += 1) {
      clock.set(DateTime.utc(2026, 8, 31, 8, 0, index));
      created.add(
        await repository.create(
          _newTransaction(
            amountCents: 1000 + index,
            type: index.isEven
                ? TransactionType.expense
                : TransactionType.income,
            category: index.isEven ? 'groceries_food' : 'salary',
            note: index % 3 == 0 ? null : '备份测试 $index',
            originalText: '备份测试 $index',
            transactionDate: index < 80 ? '2026-08-31' : '2026-07-31',
          ),
        ),
      );
    }

    clock.set(DateTime.utc(2026, 8, 31, 12));
    for (final entry in created.take(10)) {
      await repository.softDelete(entry.id);
    }

    final beforeAll = await dataSource.listAllForBackup();
    final beforeTotalExpense = _sumActiveByType(
      beforeAll,
      TransactionType.expense,
    );
    final beforeTotalIncome = _sumActiveByType(
      beforeAll,
      TransactionType.income,
    );
    final beforeTodayExpense = await repository.todayExpenseCents();
    final beforeMonthExpense = await repository.monthExpenseCents();
    final beforeMonthIncome = await repository.monthIncomeCents();
    final backup = await backupService.exportBackup();

    await database.close();
    await File(databasePath).delete();
    database = await AppDatabase.openAtPath(
      databasePath,
      databaseFactory: databaseFactoryFfi,
    );
    dataSource = TransactionLocalDataSource(database);
    repository = TransactionRepository(dataSource, clock: clock);
    backupService = BackupService(
      dataSource: dataSource,
      clock: clock,
      backupDirectoryPath: path.join(tempDir.path, 'backups'),
    );

    expect(await dataSource.listAllForBackup(), isEmpty);
    final restored = await backupService.importBackup(backup.filePath);
    final afterAll = await dataSource.listAllForBackup();

    expect(restored.transactionCount, 100);
    expect(restored.deletedCount, 10);
    expect(afterAll, hasLength(100));
    expect(
      afterAll.map((entry) => entry.id),
      beforeAll.map((entry) => entry.id),
    );
    for (var index = 0; index < beforeAll.length; index += 1) {
      expect(afterAll[index].toMap(), beforeAll[index].toMap());
    }
    expect(await repository.list(limit: 200), hasLength(90));
    expect(await repository.todayExpenseCents(), beforeTodayExpense);
    expect(await repository.monthExpenseCents(), beforeMonthExpense);
    expect(await repository.monthIncomeCents(), beforeMonthIncome);
    expect(
      _sumActiveByType(afterAll, TransactionType.expense),
      beforeTotalExpense,
    );
    expect(
      _sumActiveByType(afterAll, TransactionType.income),
      beforeTotalIncome,
    );
    expect(
      afterAll.where((entry) => entry.isDeleted).map((entry) => entry.id),
      created.take(10).map((entry) => entry.id),
    );
  });

  test('非法备份被拒绝且不会清空现有账目', () async {
    await repository.create(_newTransaction());
    final invalidFile = File(path.join(tempDir.path, 'invalid.json'));
    await invalidFile.writeAsString(
      jsonEncode({
        'backup_version': 99,
        'app_version': BackupService.appVersion,
        'database_version': 1,
        'created_at': '2026-08-31T10:30:00Z',
        'transactions': <Object?>[],
      }),
    );

    await expectLater(
      backupService.importBackup(invalidFile.path),
      throwsA(isA<BackupException>()),
    );
    expect(await repository.list(), hasLength(1));
  });
}

int _sumActiveByType(
  Iterable<LedgerTransaction> entries,
  TransactionType type,
) {
  return entries
      .where((entry) => !entry.isDeleted && entry.type == type)
      .fold(0, (sum, entry) => sum + entry.amountCents);
}

NewLedgerTransaction _newTransaction({
  int amountCents = 3500,
  TransactionType type = TransactionType.expense,
  String category = 'groceries_food',
  String? note = '买菜',
  String originalText = '35块买菜',
  String transactionDate = '2026-08-31',
}) {
  return NewLedgerTransaction(
    amountCents: amountCents,
    type: type,
    category: category,
    note: note,
    originalText: originalText,
    transactionDate: transactionDate,
  );
}

final class MutableClock implements Clock {
  MutableClock(this._now);

  DateTime _now;

  void set(DateTime now) {
    _now = now;
  }

  @override
  DateTime now() => _now;
}

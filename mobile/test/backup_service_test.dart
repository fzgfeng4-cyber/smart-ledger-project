import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:smartledger/data/backup/backup_service.dart';
import 'package:smartledger/data/budget/budget_local_data_source.dart';
import 'package:smartledger/data/import/import_coordinator.dart';
import 'package:smartledger/data/import/import_file_picker.dart';
import 'package:smartledger/data/repositories/transaction_repository.dart';
import 'package:smartledger/data/sqlite/app_database.dart';
import 'package:smartledger/data/sqlite/database_schema.dart';
import 'package:smartledger/data/sqlite/transaction_local_data_source.dart';
import 'package:smartledger/domain/budget/budget.dart';
import 'package:smartledger/domain/import/import_contract.dart';
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
  late BudgetLocalDataSource budgetDataSource;
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
    budgetDataSource = BudgetLocalDataSource(database);
    repository = TransactionRepository(dataSource, clock: clock);
    backupService = BackupService(
      dataSource: dataSource,
      budgetDataSource: budgetDataSource,
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
    final budget = await budgetDataSource.insert(
      const NewBudget(
        categoryCode: 'groceries_food',
        month: '2026-08',
        amountCents: 50000,
      ),
      now: clock.now(),
    );

    final result = await backupService.exportBackup();
    final file = File(result.filePath);
    final document =
        jsonDecode(await file.readAsString()) as Map<String, dynamic>;

    expect(result.transactionCount, 2);
    expect(result.deletedCount, 1);
    expect(result.budgetCount, 1);
    expect(document['backup_version'], BackupService.backupVersion);
    expect(document['app_version'], BackupService.appVersion);
    expect(document['database_version'], DatabaseSchema.version);
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
    final budgets = document['budgets'] as List<dynamic>;
    expect(budgets, hasLength(1));
    expect((budgets.single as Map<String, dynamic>)['id'], budget.id);
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
    budgetDataSource = BudgetLocalDataSource(database);
    repository = TransactionRepository(dataSource, clock: clock);
    backupService = BackupService(
      dataSource: dataSource,
      budgetDataSource: budgetDataSource,
      clock: clock,
      backupDirectoryPath: path.join(tempDir.path, 'backups'),
    );

    expect(await dataSource.listAllForBackup(), isEmpty);
    final restored = await backupService.importBackup(backup.filePath);
    final afterAll = await dataSource.listAllForBackup();

    expect(restored.transactionCount, 100);
    expect(restored.deletedCount, 10);
    expect(restored.budgetCount, 0);
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

  test('导入批次随备份恢复后再次导入仍被幂等拦截', () async {
    const csv = '''支付宝交易记录明细
交易时间,交易分类,收/支,金额,交易对方,商品说明,交易订单号,资金状态
2026-08-31 12:30:00,餐饮,支出,35.00,星巴克,咖啡,ORDER-1,交易成功
''';
    final importedFile = PickedImportFile(
      fileName: '支付宝账单.csv',
      bytes: utf8.encode(csv),
    );
    final coordinator = ImportCoordinator(
      repository: repository,
      clock: clock,
    );
    final batch = await coordinator.parsePickedFile(
      ImportSourceType.alipayCsv,
      importedFile,
    );
    final readyBatch = batch.confirm(3);

    final saved = await coordinator.saveBatch(
      readyBatch,
      readyBatch.transactionsToSave,
    );
    expect(saved, hasLength(1));
    final backup = await backupService.exportBackup();

    await database.close();
    await File(databasePath).delete();
    database = await AppDatabase.openAtPath(
      databasePath,
      databaseFactory: databaseFactoryFfi,
    );
    dataSource = TransactionLocalDataSource(database);
    budgetDataSource = BudgetLocalDataSource(database);
    repository = TransactionRepository(dataSource, clock: clock);
    backupService = BackupService(
      dataSource: dataSource,
      budgetDataSource: budgetDataSource,
      clock: clock,
      backupDirectoryPath: path.join(tempDir.path, 'backups'),
    );

    final restored = await backupService.importBackup(backup.filePath);
    expect(restored.transactionCount, 1);
    expect(
      await database.query(DatabaseSchema.importBatchesTable),
      hasLength(1),
    );

    final coordinatorAfterRestore = ImportCoordinator(
      repository: repository,
      clock: clock,
    );
    final parsedAgain = await coordinatorAfterRestore.parsePickedFile(
      ImportSourceType.alipayCsv,
      importedFile,
    );
    final readyAgain = parsedAgain.confirm(3);

    await expectLater(
      coordinatorAfterRestore.saveBatch(
        readyAgain,
        readyAgain.transactionsToSave,
      ),
      throwsA(
        isA<ImportCoordinatorException>().having(
          (error) => error.message,
          'message',
          '这份账单文件已经导入过，未重复写入。',
        ),
      ),
    );
    expect(await repository.list(), hasLength(1));
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

  test('备份版本与数据库版本不匹配时拒绝恢复且不清空现有账目', () async {
    await repository.create(_newTransaction());
    final mismatchedFile = File(path.join(tempDir.path, 'mismatched.json'));
    await mismatchedFile.writeAsString(
      jsonEncode({
        'backup_version': BackupService.legacyBackupVersion,
        'app_version': BackupService.appVersion,
        'database_version': DatabaseSchema.version,
        'created_at': '2026-08-31T10:30:00Z',
        'transactions': <Object?>[],
      }),
    );

    await expectLater(
      backupService.importBackup(mismatchedFile.path),
      throwsA(isA<BackupException>()),
    );
    expect(await repository.list(), hasLength(1));
  });

  test('V1 JSON 备份可恢复到 V2，缺失预算按无预算处理', () async {
    await budgetDataSource.insert(
      const NewBudget(
        categoryCode: 'dining',
        month: '2026-08',
        amountCents: 10000,
      ),
      now: clock.now(),
    );
    final oldBackup = File(path.join(tempDir.path, 'v1-backup.json'));
    await oldBackup.writeAsString(
      jsonEncode({
        'backup_version': BackupService.legacyBackupVersion,
        'app_version': BackupService.appVersion,
        'database_version': 1,
        'created_at': '2026-08-31T10:30:00Z',
        'transactions': [
          {
            'id': 7,
            'amount_cents': 3580,
            'type': 'expense',
            'category': 'groceries_food',
            'note': '买菜',
            'original_text': '35.80元买菜',
            'transaction_date': '2026-08-31',
            'created_at': '2026-08-31T10:00:00Z',
            'updated_at': '2026-08-31T10:00:00Z',
            'deleted_at': null,
          },
        ],
      }),
    );

    final result = await backupService.importBackup(oldBackup.path);
    final restored = await dataSource.findById(7);

    expect(result.transactionCount, 1);
    expect(result.budgetCount, 0);
    expect(restored, isNotNull);
    expect(restored!.amountCents, 3580);
    expect(restored.category, 'groceries_food');
    expect(await database.query(DatabaseSchema.budgetsTable), isEmpty);
  });

  test('V1 JSON 整数型 double 金额和旧分类可以恢复，日期原值不被静默改写', () async {
    final oldBackup = File(path.join(tempDir.path, 'v1-legacy-values.json'));
    await oldBackup.writeAsString(
      jsonEncode({
        'backup_version': BackupService.legacyBackupVersion,
        'app_version': BackupService.appVersion,
        'database_version': 1,
        'created_at': '2026-08-31T10:30:00Z',
        'transactions': [
          {
            'id': 8,
            'amount_cents': 3580.0,
            'type': 'expense',
            'category': 'legacy_unknown',
            'note': '旧备注',
            'original_text': '旧分类账目',
            'transaction_date': '未来或非法日期',
            'created_at': '2026-08-31T10:00:00Z',
            'updated_at': '2026-08-31T10:00:00Z',
            'deleted_at': null,
          },
        ],
      }),
    );

    final result = await backupService.importBackup(oldBackup.path);
    final restored = await dataSource.findById(8);

    expect(result.transactionCount, 1);
    expect(restored, isNotNull);
    expect(restored!.amountCents, 3580);
    expect(restored.category, 'other_expense');
    expect(restored.note, contains('原分类：legacy_unknown'));
    expect(restored.transactionDate, '未来或非法日期');
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

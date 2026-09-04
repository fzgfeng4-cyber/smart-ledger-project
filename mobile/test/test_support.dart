import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:smartledger/data/backup/backup_service.dart';
import 'package:smartledger/data/budget/budget_local_data_source.dart';
import 'package:smartledger/data/budget/budget_repository.dart';
import 'package:smartledger/data/repositories/transaction_repository.dart';
import 'package:smartledger/data/search/transaction_search_repository.dart';
import 'package:smartledger/data/sqlite/app_database.dart';
import 'package:smartledger/data/sqlite/database_schema.dart';
import 'package:smartledger/data/sqlite/transaction_local_data_source.dart';
import 'package:smartledger/domain/models/ledger_transaction.dart';
import 'package:smartledger/domain/models/transaction_type.dart';
import 'package:smartledger/shared/clock.dart';
import 'package:smartledger/ui/ledger_ui_controller.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

final class TestLedgerFixture {
  TestLedgerFixture._({
    required this.tempDir,
    required this.database,
    required this.clock,
    required this.repository,
    required this.searchRepository,
    required this.backupService,
    required this.budgetRepository,
    required this.pageSize,
  });

  final Directory tempDir;
  Database database;
  final MutableClock clock;
  final TransactionRepository repository;
  final TransactionSearchRepository searchRepository;
  final BackupService backupService;
  final BudgetRepository budgetRepository;
  final int pageSize;
  late LedgerUiController controller;
  bool _databaseClosed = false;

  static Future<TestLedgerFixture> create({
    DateTime? now,
    int pageSize = 20,
  }) async {
    sqfliteFfiInit();
    var suffix = DateTime.now().microsecondsSinceEpoch;
    late Directory tempDir;
    while (true) {
      final candidate = Directory(
        path.join(Directory.systemTemp.path, 'smartledger_v2_test_$suffix'),
      );
      try {
        candidate.createSync(recursive: true);
        tempDir = candidate;
        break;
      } on FileSystemException {
        suffix += 1;
      }
    }
    final databasePath = path.join(tempDir.path, 'smart-ledger-test.sqlite');
    final database = await AppDatabase.openAtPath(
      databasePath,
      databaseFactory: databaseFactoryFfi,
    );
    final clock = MutableClock(now ?? DateTime(2026, 8, 31, 10, 30));
    final dataSource = TransactionLocalDataSource(database);
    final budgetDataSource = BudgetLocalDataSource(database);
    final repository = TransactionRepository(dataSource, clock: clock);
    final budgetRepository = BudgetRepository(budgetDataSource, clock: clock);
    final searchRepository = TransactionSearchRepository(dataSource);
    final backupService = BackupService(
      dataSource: dataSource,
      budgetDataSource: budgetDataSource,
      clock: clock,
      backupDirectoryPath: path.join(tempDir.path, 'backups'),
    );
    final controller = LedgerUiController(
      repository: repository,
      searchRepository: searchRepository,
      backupService: backupService,
      budgetRepository: budgetRepository,
      clock: clock,
      pageSize: pageSize,
    );

    final fixture = TestLedgerFixture._(
      tempDir: tempDir,
      database: database,
      clock: clock,
      repository: repository,
      searchRepository: searchRepository,
      backupService: backupService,
      budgetRepository: budgetRepository,
      pageSize: pageSize,
    );
    fixture.controller = controller;
    return fixture;
  }

  Future<LedgerTransaction> seed({
    int amountCents = 3500,
    TransactionType type = TransactionType.expense,
    String category = 'groceries_food',
    String? note = '买菜',
    String originalText = '35块买菜',
    String transactionDate = '2026-08-31',
  }) {
    return repository.create(
      NewLedgerTransaction(
        amountCents: amountCents,
        type: type,
        category: category,
        note: note,
        originalText: originalText,
        transactionDate: transactionDate,
      ),
    );
  }

  Future<void> closeDatabase() async {
    if (_databaseClosed) {
      return;
    }
    await database.close();
    _databaseClosed = true;
  }

  Future<void> reset() async {
    await database.delete(DatabaseSchema.budgetsTable);
    await database.delete(DatabaseSchema.importBatchesTable);
    await database.delete(DatabaseSchema.transactionsTable);
    recreateController();
    await controller.initialize();
  }

  void recreateController() {
    controller.dispose();
    controller = LedgerUiController(
      repository: repository,
      searchRepository: searchRepository,
      backupService: backupService,
      budgetRepository: budgetRepository,
      clock: clock,
      pageSize: pageSize,
    );
  }

  Future<void> dispose() async {
    controller.dispose();
    await closeDatabase();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  }
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

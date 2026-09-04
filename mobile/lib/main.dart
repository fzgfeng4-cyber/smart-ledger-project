import 'package:flutter/material.dart';

import 'data/backup/backup_service.dart';
import 'data/budget/budget_local_data_source.dart';
import 'data/budget/budget_repository.dart';
import 'data/repositories/transaction_repository.dart';
import 'data/search/transaction_search_repository.dart';
import 'data/sqlite/app_database.dart';
import 'data/sqlite/transaction_local_data_source.dart';
import 'domain/parser/transaction_parser.dart';
import 'shared/clock.dart';
import 'app/smart_ledger_app.dart';
import 'ui/ledger_ui_controller.dart';
import 'ui/ocr/ocr_capture.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final database = AppDatabase();
  final db = await database.open();
  final clock = const SystemClock();
  final dataSource = TransactionLocalDataSource(db);
  final budgetDataSource = BudgetLocalDataSource(db);
  final repository = TransactionRepository(dataSource, clock: clock);
  final searchRepository = TransactionSearchRepository(dataSource);
  final budgetRepository = BudgetRepository(budgetDataSource, clock: clock);
  final backupService = BackupService(
    dataSource: dataSource,
    budgetDataSource: budgetDataSource,
    clock: clock,
  );
  final controller = LedgerUiController(
    repository: repository,
    searchRepository: searchRepository,
    backupService: backupService,
    budgetRepository: budgetRepository,
    parser: TransactionParser(clock: clock),
    clock: clock,
  );
  await controller.initialize();

  runApp(
    SmartLedgerApp(
      controller: controller,
      ocrCapture: AndroidOcrCaptureService(),
    ),
  );
}

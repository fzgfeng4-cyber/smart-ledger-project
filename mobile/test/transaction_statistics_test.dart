import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:smartledger/data/repositories/transaction_repository.dart';
import 'package:smartledger/data/sqlite/app_database.dart';
import 'package:smartledger/data/sqlite/database_schema.dart';
import 'package:smartledger/data/sqlite/transaction_local_data_source.dart';
import 'package:smartledger/domain/models/ledger_transaction.dart';
import 'package:smartledger/domain/models/transaction_type.dart';
import 'package:smartledger/domain/statistics/statistics_date_range.dart';
import 'package:smartledger/domain/statistics/statistics_summary.dart';
import 'package:smartledger/shared/clock.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  late Directory tempDir;
  late Database db;
  late MutableClock clock;
  late TransactionRepository repository;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp(
      'smart_ledger_statistics_test_',
    );
    final databasePath = path.join(tempDir.path, 'smart-ledger-test.sqlite');
    db = await AppDatabase.openAtPath(
      databasePath,
      databaseFactory: databaseFactoryFfi,
    );
    clock = MutableClock(DateTime.utc(2026, 8, 31, 10, 30));
    repository = TransactionRepository(
      TransactionLocalDataSource(db),
      clock: clock,
    );
  });

  tearDown(() async {
    await db.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('空数据返回零汇总且总额为零时占比为零', () async {
    final result = await repository.statisticsForDateRange(
      _range('2026-08-01', '2026-09-01'),
    );

    expect(result.expenseTotalCents, 0);
    expect(result.incomeTotalCents, 0);
    expect(result.expenseCategories, isEmpty);

    final zeroSummary = StatisticsSummary.calculate(
      range: _range('2026-08-01', '2026-09-01'),
      expenseTotalCents: 0,
      incomeTotalCents: 1200,
      expenseCategories: const [
        StatisticsCategoryAmount(categoryCode: 'dining', amountCents: 0),
      ],
    );
    expect(zeroSummary.expenseCategories.single.proportion, 0.0);
    expect(zeroSummary.expenseCategories.single.percentage, 0.0);
  });

  test('多个分类按稳定 code 顺序聚合并从目录读取标签', () async {
    await repository.create(
      _newTransaction(amountCents: 125, category: 'groceries_food'),
    );
    await repository.create(
      _newTransaction(amountCents: 75, category: 'dining'),
    );
    await repository.create(
      _newTransaction(amountCents: 300, category: 'groceries_food'),
    );
    await repository.create(
      _newTransaction(amountCents: 50, category: 'transportation'),
    );

    final result = await repository.statisticsForDateRange(
      _range('2026-08-01', '2026-09-01'),
    );

    expect(result.expenseTotalCents, 550);
    expect(result.incomeTotalCents, 0);
    expect(result.expenseCategories.map((category) => category.code), [
      'dining',
      'groceries_food',
      'transportation',
    ]);
    expect(result.expenseCategories.map((category) => category.label), [
      '餐饮',
      '买菜/食品',
      '交通',
    ]);
    expect(result.expenseCategories.map((category) => category.amountCents), [
      75,
      425,
      50,
    ]);
  });

  test('日期范围是左闭右开，跨月边界只计入范围内日期', () async {
    clock.set(DateTime.utc(2026, 9, 2, 10, 30));
    await repository.create(
      _newTransaction(amountCents: 100, transactionDate: '2026-08-31'),
    );
    await repository.create(
      _newTransaction(amountCents: 200, transactionDate: '2026-09-01'),
    );
    await repository.create(
      _newTransaction(amountCents: 300, transactionDate: '2026-09-02'),
    );

    final august = await repository.statisticsForDateRange(
      _range('2026-08-01', '2026-09-01'),
    );
    final septemberFirst = await repository.statisticsForDateRange(
      _range('2026-09-01', '2026-09-02'),
    );

    expect(august.expenseTotalCents, 100);
    expect(septemberFirst.expenseTotalCents, 200);
  });

  test('软删除记录不进入支出、收入或分类统计', () async {
    final kept = await repository.create(_newTransaction(amountCents: 500));
    final deleted = await repository.create(
      _newTransaction(
        amountCents: 700,
        type: TransactionType.income,
        category: 'salary',
      ),
    );
    await repository.softDelete(deleted.id);

    final result = await repository.statisticsForDateRange(
      _range('2026-08-01', '2026-09-01'),
    );

    expect(kept.amountCents, 500);
    expect(result.expenseTotalCents, 500);
    expect(result.incomeTotalCents, 0);
    expect(result.expenseCategories.single.amountCents, 500);
  });

  test('收入不影响支出占比，金额始终按整数分精确求和', () async {
    await repository.create(
      _newTransaction(amountCents: 1, category: 'dining'),
    );
    await repository.create(
      _newTransaction(amountCents: 2, category: 'groceries_food'),
    );
    await repository.create(
      _newTransaction(
        amountCents: 999999,
        type: TransactionType.income,
        category: 'salary',
      ),
    );

    final result = await repository.statisticsForDateRange(
      _range('2026-08-01', '2026-09-01'),
    );

    expect(result.expenseTotalCents, 3);
    expect(result.incomeTotalCents, 999999);
    expect(result.expenseCategories.map((category) => category.amountCents), [
      1,
      2,
    ]);
    expect(result.expenseCategories[0].proportion, closeTo(1 / 3, 1e-12));
    expect(result.expenseCategories[1].proportion, closeTo(2 / 3, 1e-12));
  });

  test('当前月统计使用注入 Clock 计算月份范围', () async {
    clock.set(DateTime.utc(2026, 9, 2, 10, 30));
    await repository.create(
      _newTransaction(amountCents: 800, transactionDate: '2026-08-31'),
    );
    await repository.create(
      _newTransaction(amountCents: 900, transactionDate: '2026-09-01'),
    );

    final result = await repository.currentMonthStatistics();

    expect(result.range.startDateInclusive, '2026-09-01');
    expect(result.range.endDateExclusive, '2026-10-01');
    expect(result.expenseTotalCents, 900);
  });

  test('当前月统计不计入业务日之后的未来日期', () async {
    clock.set(DateTime.utc(2026, 9, 2, 10, 30));
    await repository.create(
      _newTransaction(amountCents: 900, transactionDate: '2026-09-02'),
    );
    await db.insert(DatabaseSchema.transactionsTable, {
      'amount_cents': 300,
      'type': 'expense',
      'category': 'dining',
      'note': '未来日期',
      'original_text': '未来日期账目',
      'transaction_date': '2026-09-03',
      'created_at': '2026-09-02T10:00:00Z',
      'updated_at': '2026-09-02T10:00:00Z',
      'deleted_at': null,
    });

    final result = await repository.currentMonthStatistics();

    expect(result.expenseTotalCents, 900);
  });

  test('非法和未来日期不会污染统计', () async {
    await repository.create(
      _newTransaction(amountCents: 100, transactionDate: '2026-08-31'),
    );
    await db.insert(DatabaseSchema.transactionsTable, {
      'amount_cents': 200,
      'type': 'expense',
      'category': 'dining',
      'note': '非法日期',
      'original_text': '非法日期账目',
      'transaction_date': '2026-08-99',
      'created_at': '2026-08-31T10:00:00Z',
      'updated_at': '2026-08-31T10:00:00Z',
      'deleted_at': null,
    });
    await db.insert(DatabaseSchema.transactionsTable, {
      'amount_cents': 300,
      'type': 'expense',
      'category': 'dining',
      'note': '未来日期',
      'original_text': '未来日期账目',
      'transaction_date': '2026-09-01',
      'created_at': '2026-08-31T10:00:00Z',
      'updated_at': '2026-08-31T10:00:00Z',
      'deleted_at': null,
    });

    final result = await repository.statisticsForDateRange(
      _range('2026-08-01', '2026-09-02'),
    );

    expect(result.expenseTotalCents, 100);
    expect(result.expenseCategories.single.amountCents, 100);
  });
}

StatisticsDateRange _range(String start, String end) {
  return StatisticsDateRange(startDateInclusive: start, endDateExclusive: end);
}

NewLedgerTransaction _newTransaction({
  int amountCents = 3500,
  TransactionType type = TransactionType.expense,
  String category = 'groceries_food',
  String? note = '测试',
  String originalText = '测试账目',
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

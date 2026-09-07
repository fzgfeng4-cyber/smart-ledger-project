import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:smartledger/data/repositories/transaction_repository.dart';
import 'package:smartledger/data/sqlite/app_database.dart';
import 'package:smartledger/data/sqlite/database_schema.dart';
import 'package:smartledger/data/sqlite/transaction_local_data_source.dart';
import 'package:smartledger/domain/models/ledger_transaction.dart';
import 'package:smartledger/domain/models/transaction_type.dart';
import 'package:smartledger/domain/statistics/statistics_bucket_unit.dart';
import 'package:smartledger/domain/statistics/statistics_date_range.dart';
import 'package:smartledger/domain/statistics/statistics_summary.dart';
import 'package:smartledger/domain/validation/transaction_validator.dart';
import 'package:smartledger/shared/clock.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  late Directory tempDir;
  late Database db;
  late MutableClock clock;
  late TransactionRepository repository;
  var databaseClosed = false;

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
    databaseClosed = false;
  });

  tearDown(() async {
    if (!databaseClosed) {
      await db.close();
    }
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

  test('统计汇总拒绝非法日期范围且不访问 SQLite', () async {
    await db.close();
    databaseClosed = true;

    final invalidRanges = [
      _range('2026-8-01', '2026-09-01'),
      _range('2026-08-01', '2026-9-01'),
      _range('2026-02-30', '2026-03-01'),
      _range('2026-08-01', '2026-08-01'),
      _range('2026-09-01', '2026-08-01'),
    ];

    for (final range in invalidRanges) {
      await expectLater(
        repository.statisticsForDateRange(range),
        throwsA(_invalidStatisticsRangeMatcher),
      );
    }
  });

  test('时间序列拒绝与统计汇总一致的非法日期范围且不先生成时间桶', () async {
    await db.close();
    databaseClosed = true;

    for (final range in [
      _range('2026-8-01', '2026-09-01'),
      _range('2026-08-01', '2026-02-30'),
      _range('2026-08-01', '2026-08-01'),
      _range('2026-09-01', '2026-08-01'),
    ]) {
      await expectLater(
        repository.timeSeriesForDateRange(
          range,
          unit: StatisticsBucketUnit.day,
        ),
        throwsA(_invalidStatisticsRangeMatcher),
      );
    }
  });

  test('日期桶直接入口对非法日期统一抛出统计校验异常', () {
    final invalidRange = _range('2026-02-30', '2026-03-01');

    expect(
      () => invalidRange.bucketRanges(StatisticsBucketUnit.day),
      throwsA(_invalidStatisticsRangeMatcher),
    );
    expect(
      () => StatisticsDateRange.bucketKeyForDate(
        '2026-02-30',
        StatisticsBucketUnit.day,
      ),
      throwsA(_invalidStatisticsRangeMatcher),
    );
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

  test('月度时间序列补齐每天空桶并按日期正序排列', () async {
    await repository.create(
      _newTransaction(amountCents: 100, transactionDate: '2026-08-01'),
    );
    await repository.create(
      _newTransaction(
        amountCents: 250,
        type: TransactionType.income,
        category: 'salary',
        transactionDate: '2026-08-15',
      ),
    );
    await repository.create(
      _newTransaction(amountCents: 300, transactionDate: '2026-08-31'),
    );

    final result = await repository.timeSeriesForDateRange(
      StatisticsDateRange.month(DateTime(2026, 8)),
      unit: StatisticsBucketUnit.day,
    );

    expect(result.unit, StatisticsBucketUnit.day);
    expect(result.buckets, hasLength(31));
    expect(result.buckets.first.key, '2026-08-01');
    expect(result.buckets.last.key, '2026-08-31');
    expect(result.buckets[0].expenseTotalCents, 100);
    expect(result.buckets[1].expenseTotalCents, 0);
    expect(result.buckets[14].incomeTotalCents, 250);
    expect(result.buckets[30].expenseTotalCents, 300);
    expect(
      result.buckets.map((bucket) => bucket.startDateInclusive).toList(),
      orderedEquals(
        List<String>.generate(
          31,
          (index) => '2026-08-${(index + 1).toString().padLeft(2, '0')}',
        ),
      ),
    );
  });

  test('空月份返回完整的每日零元桶', () async {
    final result = await repository.timeSeriesForDateRange(
      StatisticsDateRange.month(DateTime(2026, 2)),
      unit: StatisticsBucketUnit.day,
    );

    expect(result.buckets, hasLength(28));
    expect(
      result.buckets.map((bucket) => bucket.key),
      List<String>.generate(
        28,
        (index) => '2026-02-${(index + 1).toString().padLeft(2, '0')}',
      ),
    );
    expect(
      result.buckets.every(
        (bucket) =>
            bucket.expenseTotalCents == 0 && bucket.incomeTotalCents == 0,
      ),
      isTrue,
    );
  });

  test('空年份返回十二个月零元桶', () async {
    final result = await repository.timeSeriesForDateRange(
      StatisticsDateRange.year(DateTime(2025)),
      unit: StatisticsBucketUnit.month,
    );

    expect(result.buckets, hasLength(12));
    expect(
      result.buckets.map((bucket) => bucket.key),
      List<String>.generate(
        12,
        (index) => '2025-${(index + 1).toString().padLeft(2, '0')}',
      ),
    );
    expect(
      result.buckets.every(
        (bucket) =>
            bucket.expenseTotalCents == 0 && bucket.incomeTotalCents == 0,
      ),
      isTrue,
    );
  });

  test('同一天的多笔支出在同一个 day 桶内精确合计', () async {
    await repository.create(
      _newTransaction(amountCents: 125, transactionDate: '2026-08-30'),
    );
    await repository.create(
      _newTransaction(amountCents: 375, transactionDate: '2026-08-30'),
    );

    final result = await repository.timeSeriesForDateRange(
      StatisticsDateRange.month(DateTime(2026, 8)),
      unit: StatisticsBucketUnit.day,
    );
    final bucket = result.buckets.singleWhere(
      (candidate) => candidate.key == '2026-08-30',
    );

    expect(bucket.expenseTotalCents, 500);
    expect(bucket.incomeTotalCents, 0);
  });

  test('同一时间桶内收入和支出分别累计', () async {
    await repository.create(
      _newTransaction(amountCents: 125, transactionDate: '2026-08-20'),
    );
    await repository.create(
      _newTransaction(
        amountCents: 900,
        type: TransactionType.income,
        category: 'salary',
        transactionDate: '2026-08-20',
      ),
    );

    final result = await repository.timeSeriesForDateRange(
      StatisticsDateRange.month(DateTime(2026, 8)),
      unit: StatisticsBucketUnit.day,
    );
    final bucket = result.buckets.singleWhere(
      (candidate) => candidate.key == '2026-08-20',
    );

    expect(bucket.expenseTotalCents, 125);
    expect(bucket.incomeTotalCents, 900);
  });

  test('跨月日期不会混入同一个 month 桶', () async {
    await repository.create(
      _newTransaction(amountCents: 100, transactionDate: '2026-01-31'),
    );
    await repository.create(
      _newTransaction(amountCents: 200, transactionDate: '2026-02-01'),
    );

    final result = await repository.timeSeriesForDateRange(
      _range('2026-01-01', '2026-03-01'),
      unit: StatisticsBucketUnit.month,
    );

    expect(result.buckets, hasLength(2));
    expect(result.buckets[0].key, '2026-01');
    expect(result.buckets[0].expenseTotalCents, 100);
    expect(result.buckets[1].key, '2026-02');
    expect(result.buckets[1].expenseTotalCents, 200);
  });

  test('跨年日期不会混入同一个 year 桶', () async {
    await repository.create(
      _newTransaction(amountCents: 100, transactionDate: '2025-12-31'),
    );
    await repository.create(
      _newTransaction(
        amountCents: 200,
        type: TransactionType.income,
        category: 'salary',
        transactionDate: '2026-01-01',
      ),
    );

    final result = await repository.timeSeriesForDateRange(
      _range('2025-12-01', '2026-02-01'),
      unit: StatisticsBucketUnit.year,
    );

    expect(result.buckets, hasLength(2));
    expect(result.buckets[0].key, '2025');
    expect(result.buckets[0].expenseTotalCents, 100);
    expect(result.buckets[0].incomeTotalCents, 0);
    expect(result.buckets[1].key, '2026');
    expect(result.buckets[1].expenseTotalCents, 0);
    expect(result.buckets[1].incomeTotalCents, 200);
  });

  test('缺少交易的日期或月份仍保留零元桶', () async {
    await repository.create(
      _newTransaction(amountCents: 100, transactionDate: '2026-01-15'),
    );

    final daily = await repository.timeSeriesForDateRange(
      _range('2026-01-01', '2026-02-01'),
      unit: StatisticsBucketUnit.day,
    );
    final monthly = await repository.timeSeriesForDateRange(
      StatisticsDateRange.year(DateTime(2026)),
      unit: StatisticsBucketUnit.month,
    );

    expect(
      daily.buckets
          .singleWhere((bucket) => bucket.key == '2026-01-14')
          .expenseTotalCents,
      0,
    );
    expect(
      daily.buckets
          .singleWhere((bucket) => bucket.key == '2026-01-15')
          .expenseTotalCents,
      100,
    );
    expect(
      daily.buckets
          .singleWhere((bucket) => bucket.key == '2026-01-16')
          .expenseTotalCents,
      0,
    );
    expect(
      monthly.buckets
          .singleWhere((bucket) => bucket.key == '2026-02')
          .expenseTotalCents,
      0,
    );
  });

  test('大金额始终按整数分和 BigInt 累计，不产生浮点误差', () async {
    const largeAmountCents = 9007199254740991;
    await repository.create(
      _newTransaction(
        amountCents: largeAmountCents,
        transactionDate: '2026-08-30',
      ),
    );
    await repository.create(
      _newTransaction(
        amountCents: largeAmountCents,
        transactionDate: '2026-08-30',
      ),
    );

    final result = await repository.timeSeriesForDateRange(
      StatisticsDateRange.month(DateTime(2026, 8)),
      unit: StatisticsBucketUnit.day,
    );
    final bucket = result.buckets.singleWhere(
      (candidate) => candidate.key == '2026-08-30',
    );

    expect(bucket.expenseTotalCents, 18014398509481982);
  });

  test('年度时间序列始终返回十二个月并按月份正序排列', () async {
    await repository.create(
      _newTransaction(amountCents: 100, transactionDate: '2026-01-05'),
    );
    await repository.create(
      _newTransaction(
        amountCents: 200,
        type: TransactionType.income,
        category: 'salary',
        transactionDate: '2026-02-10',
      ),
    );
    await repository.create(
      _newTransaction(amountCents: 300, transactionDate: '2026-08-31'),
    );

    final result = await repository.timeSeriesForDateRange(
      StatisticsDateRange.year(DateTime(2026, 8, 31)),
      unit: StatisticsBucketUnit.month,
    );

    expect(result.range.startDateInclusive, '2026-01-01');
    expect(result.range.endDateExclusive, '2027-01-01');
    expect(result.buckets, hasLength(12));
    expect(result.buckets.map((bucket) => bucket.key), [
      '2026-01',
      '2026-02',
      '2026-03',
      '2026-04',
      '2026-05',
      '2026-06',
      '2026-07',
      '2026-08',
      '2026-09',
      '2026-10',
      '2026-11',
      '2026-12',
    ]);
    expect(result.buckets[0].expenseTotalCents, 100);
    expect(result.buckets[1].incomeTotalCents, 200);
    expect(result.buckets[7].expenseTotalCents, 300);
    expect(result.buckets[8].expenseTotalCents, 0);
    expect(result.buckets.last.startDateInclusive, '2026-12-01');
    expect(result.buckets.last.endDateExclusive, '2027-01-01');
  });

  test('时间序列沿用软删除、非法日期和未来日期过滤规则', () async {
    final deleted = await repository.create(
      _newTransaction(amountCents: 700, transactionDate: '2026-08-30'),
    );
    await repository.softDelete(deleted.id);
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

    final result = await repository.timeSeriesForDateRange(
      StatisticsDateRange.year(DateTime(2026)),
      unit: StatisticsBucketUnit.month,
    );

    expect(
      result.buckets
          .singleWhere((bucket) => bucket.key == '2026-08')
          .expenseTotalCents,
      100,
    );
    expect(
      result.buckets
          .singleWhere((bucket) => bucket.key == '2026-09')
          .expenseTotalCents,
      0,
    );
  });

  test('日期范围可生成 day、month、year 三种自然时间桶', () {
    final range = StatisticsDateRange.fromDates(
      startInclusive: DateTime(2025, 12, 15),
      endExclusive: DateTime(2027, 2, 10),
    );

    final dayBuckets = range.bucketRanges(StatisticsBucketUnit.day);
    final monthBuckets = range.bucketRanges(StatisticsBucketUnit.month);
    final yearBuckets = range.bucketRanges(StatisticsBucketUnit.year);

    expect(dayBuckets.first.key, '2025-12-15');
    expect(dayBuckets.last.key, '2027-02-09');
    expect(monthBuckets.map((bucket) => bucket.key), [
      '2025-12',
      '2026-01',
      '2026-02',
      '2026-03',
      '2026-04',
      '2026-05',
      '2026-06',
      '2026-07',
      '2026-08',
      '2026-09',
      '2026-10',
      '2026-11',
      '2026-12',
      '2027-01',
      '2027-02',
    ]);
    expect(yearBuckets.map((bucket) => bucket.key), ['2025', '2026', '2027']);
    expect(monthBuckets.first.startDateInclusive, '2025-12-15');
    expect(monthBuckets.first.endDateExclusive, '2026-01-01');
    expect(monthBuckets.last.startDateInclusive, '2027-02-01');
    expect(monthBuckets.last.endDateExclusive, '2027-02-10');
  });
}

StatisticsDateRange _range(String start, String end) {
  return StatisticsDateRange(startDateInclusive: start, endDateExclusive: end);
}

Matcher get _invalidStatisticsRangeMatcher =>
    isA<TransactionValidationException>().having(
      (error) => error.message,
      'message',
      '统计日期范围无效',
    );

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

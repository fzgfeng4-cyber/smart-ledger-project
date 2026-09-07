import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:smartledger/data/repositories/transaction_repository.dart';
import 'package:smartledger/data/sqlite/app_database.dart';
import 'package:smartledger/data/sqlite/database_schema.dart';
import 'package:smartledger/data/sqlite/transaction_local_data_source.dart';
import 'package:smartledger/domain/budget/budget.dart';
import 'package:smartledger/domain/budget/budget_validator.dart';
import 'package:smartledger/domain/categories/category_catalog.dart';
import 'package:smartledger/domain/models/ledger_transaction.dart';
import 'package:smartledger/domain/models/transaction_type.dart';
import 'package:smartledger/domain/statistics/statistics_date_range.dart';
import 'package:smartledger/domain/validation/transaction_validator.dart';
import 'package:smartledger/shared/clock.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  late Directory tempDir;
  late String databasePath;
  late Database db;
  late MutableClock clock;
  late TransactionRepository repository;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('smart_ledger_data_test_');
    databasePath = path.join(tempDir.path, 'smart-ledger-test.sqlite');
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

  test('schema uses frozen transactions table and index', () async {
    expect(await db.getVersion(), DatabaseSchema.version);

    final columns = await db.rawQuery(
      'PRAGMA table_info(${DatabaseSchema.transactionsTable})',
    );
    expect(
      columns.map((column) => column['name']).toList(),
      containsAll(<String>[
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
      ]),
    );

    final indexes = await db.rawQuery(
      'PRAGMA index_list(${DatabaseSchema.transactionsTable})',
    );
    expect(
      indexes.map((index) => index['name']),
      contains('idx_transactions_date_status'),
    );
  });

  test('分类目录保留旧 code 并包含新增固定分类', () {
    expect(
      CategoryCatalog.forType(TransactionType.expense)
          .map((category) => category.code)
          .toSet(),
      equals(<String>{
        'dining',
        'groceries_food',
        'daily_necessities',
        'transportation',
        'vehicle_fuel',
        'housing',
        'communication',
        'entertainment',
        'children',
        'medical',
        'clothing_beauty',
        'education_learning',
        'travel_vacation',
        'gifts_social',
        'pets',
        'insurance',
        'digital_appliances',
        'fitness_sports',
        'debt_repayment',
        'taxes_fees',
        'charity_donation',
        'other_expense',
      }),
    );
    expect(
      CategoryCatalog.forType(TransactionType.income)
          .map((category) => category.code)
          .toSet(),
      equals(<String>{
        'salary',
        'bonus',
        'freelance',
        'business_income',
        'investment_income',
        'rental_income',
        'benefits_subsidies',
        'pension',
        'gift_red_envelope',
        'other_income',
      }),
    );
  });

  test('新增分类可进入预算、统计名称映射和 Repository 保存路径', () async {
    const newExpenseCategories = <String, String>{
      'clothing_beauty': '服饰美容',
      'education_learning': '教育学习',
      'travel_vacation': '旅行度假',
      'gifts_social': '人情往来',
      'pets': '宠物',
      'insurance': '保险',
      'digital_appliances': '数码家电',
      'fitness_sports': '运动健身',
      'debt_repayment': '债务还款',
      'taxes_fees': '税费',
      'charity_donation': '公益捐赠',
    };

    var amount = 100;
    for (final categoryCode in newExpenseCategories.keys) {
      BudgetValidator.validateCreate(
        NewBudget(
          categoryCode: categoryCode,
          month: '2026-08',
          amountCents: 10000,
        ),
      );
      await repository.create(
        _newTransaction(
          amountCents: amount,
          category: categoryCode,
          note: newExpenseCategories[categoryCode],
          originalText: newExpenseCategories[categoryCode]!,
        ),
      );
      amount += 100;
    }

    final result = await repository.statisticsForDateRange(
      const StatisticsDateRange(
        startDateInclusive: '2026-08-01',
        endDateExclusive: '2026-09-01',
      ),
    );

    expect(result.expenseCategories.map((category) => category.code), [
      'charity_donation',
      'clothing_beauty',
      'debt_repayment',
      'digital_appliances',
      'education_learning',
      'fitness_sports',
      'gifts_social',
      'insurance',
      'pets',
      'taxes_fees',
      'travel_vacation',
    ]);
    expect(result.expenseCategories.map((category) => category.label), [
      '公益捐赠',
      '服饰美容',
      '债务还款',
      '数码家电',
      '教育学习',
      '运动健身',
      '人情往来',
      '保险',
      '宠物',
      '税费',
      '旅行度假',
    ]);
  });

  test('create stores integer cents and preserves original text', () async {
    final transaction = await repository.create(
      _newTransaction(
        amountCents: 3580,
        note: ' 买菜 ',
        originalText: ' 35.80元买菜 ',
      ),
    );

    expect(transaction.id, greaterThan(0));
    expect(transaction.amountCents, 3580);
    expect(transaction.type, TransactionType.expense);
    expect(transaction.category, 'groceries_food');
    expect(transaction.note, '买菜');
    expect(transaction.originalText, ' 35.80元买菜 ');
    expect(transaction.transactionDate, '2026-08-31');
    expect(transaction.createdAt, DateTime.utc(2026, 8, 31, 10, 30));
    expect(transaction.updatedAt, transaction.createdAt);
    expect(transaction.deletedAt, isNull);
  });

  test('validation rejects invalid values before writing', () async {
    await expectLater(
      repository.create(_newTransaction(amountCents: 0)),
      throwsA(isA<TransactionValidationException>()),
    );
    await expectLater(
      repository.create(_newTransaction(category: 'salary')),
      throwsA(isA<TransactionValidationException>()),
    );
    await expectLater(
      repository.create(_newTransaction(category: 'unknown')),
      throwsA(isA<TransactionValidationException>()),
    );
    await expectLater(
      repository.create(_newTransaction(transactionDate: '2026-09-01')),
      throwsA(isA<TransactionValidationException>()),
    );
    await expectLater(
      repository.create(_newTransaction(originalText: '   ')),
      throwsA(isA<TransactionValidationException>()),
    );

    expect(await repository.list(), isEmpty);
  });

  test('update preserves id createdAt and originalText', () async {
    final created = await repository.create(_newTransaction());

    clock.set(DateTime.utc(2026, 8, 31, 11));
    final updated = await repository.update(
      created.id,
      const LedgerTransactionUpdate(
        amountCents: 1800,
        category: 'dining',
        note: null,
        transactionDate: '2026-08-30',
      ),
    );

    expect(updated, isNotNull);
    expect(updated!.id, created.id);
    expect(updated.createdAt, created.createdAt);
    expect(updated.originalText, created.originalText);
    expect(updated.amountCents, 1800);
    expect(updated.category, 'dining');
    expect(updated.note, isNull);
    expect(updated.transactionDate, '2026-08-30');
    expect(updated.updatedAt, DateTime.utc(2026, 8, 31, 11));
  });

  test(
    'soft delete hides active rows and restore keeps the same row',
    () async {
      final deleted = await repository.create(_newTransaction());
      final kept = await repository.create(
        _newTransaction(
          amountCents: 2000,
          category: 'transportation',
          note: '打车',
          originalText: '20打车',
        ),
      );

      clock.set(DateTime.utc(2026, 8, 31, 12));
      final softDeleted = await repository.softDelete(deleted.id);

      expect(softDeleted, isNotNull);
      expect(softDeleted!.id, deleted.id);
      expect(softDeleted.deletedAt, DateTime.utc(2026, 8, 31, 12));
      expect(await repository.findById(deleted.id), isNull);
      expect(
        await repository.findById(deleted.id, includeDeleted: true),
        isNotNull,
      );
      expect((await repository.list()).map((item) => item.id), [kept.id]);

      clock.set(DateTime.utc(2026, 8, 31, 12, 1));
      final restored = await repository.restore(deleted.id);

      expect(restored, isNotNull);
      expect(restored!.id, deleted.id);
      expect(restored.deletedAt, isNull);
      expect((await repository.list()).map((item) => item.id).toSet(), {
        deleted.id,
        kept.id,
      });
    },
  );

  test(
    'pagination uses transactionDate then updatedAt then id order',
    () async {
      clock.set(DateTime.utc(2026, 8, 31, 8));
      final oldDate = await repository.create(
        _newTransaction(originalText: '昨天买菜35', transactionDate: '2026-08-30'),
      );

      clock.set(DateTime.utc(2026, 8, 31, 9));
      final firstToday = await repository.create(_newTransaction());

      clock.set(DateTime.utc(2026, 8, 31, 10));
      final secondToday = await repository.create(
        _newTransaction(
          amountCents: 2000,
          category: 'transportation',
          note: '打车',
          originalText: '20打车',
        ),
      );

      expect((await repository.list(limit: 2)).map((item) => item.id), [
        secondToday.id,
        firstToday.id,
      ]);
      expect(
        (await repository.list(limit: 2, offset: 1)).map((item) => item.id),
        [firstToday.id, oldDate.id],
      );
    },
  );

  test(
    'pagination continues beyond fifty rows without duplicates or gaps',
    () async {
      final createdIds = <int>[];

      for (var index = 0; index < 55; index += 1) {
        clock.set(DateTime.utc(2026, 8, 31, 8, 0, index));
        final created = await repository.create(
          _newTransaction(
            amountCents: 1000 + index,
            note: '分页测试 $index',
            originalText: '分页测试 $index',
          ),
        );
        createdIds.add(created.id);
      }

      final firstPage = await repository.list(limit: 20);
      final secondPage = await repository.list(limit: 20, offset: 20);
      final thirdPage = await repository.list(limit: 20, offset: 40);
      final actualIds = [
        ...firstPage,
        ...secondPage,
        ...thirdPage,
      ].map((transaction) => transaction.id).toList();

      expect(actualIds, hasLength(55));
      expect(actualIds.toSet(), hasLength(55));
      expect(actualIds, createdIds.reversed.toList());
    },
  );

  test('summary uses transactionDate and excludes deleted rows', () async {
    await repository.create(_newTransaction(amountCents: 3500));
    final deletedMonthlyExpense = await repository.create(
      _newTransaction(
        amountCents: 2000,
        category: 'transportation',
        note: '打车',
        originalText: '8月1日打车20',
        transactionDate: '2026-08-01',
      ),
    );
    await repository.create(
      _newTransaction(
        amountCents: 1000,
        note: '买菜',
        originalText: '7月31日买菜10',
        transactionDate: '2026-07-31',
      ),
    );
    await repository.create(
      _newTransaction(
        amountCents: 800000,
        type: TransactionType.income,
        category: 'salary',
        note: '工资',
        originalText: '8000工资',
      ),
    );

    expect(await repository.todayExpenseCents(), 3500);
    expect(await repository.monthExpenseCents(), 5500);
    expect(await repository.monthIncomeCents(), 800000);

    await repository.softDelete(deletedMonthlyExpense.id);

    expect(await repository.todayExpenseCents(), 3500);
    expect(await repository.monthExpenseCents(), 3500);
    expect(await repository.monthIncomeCents(), 800000);
  });

  test('same sqlite file persists after close and reopen', () async {
    final created = await repository.create(_newTransaction());

    await db.close();
    db = await AppDatabase.openAtPath(
      databasePath,
      databaseFactory: databaseFactoryFfi,
    );
    final reopenedRepository = TransactionRepository(
      TransactionLocalDataSource(db),
      clock: clock,
    );

    final rows = await reopenedRepository.list();

    expect(rows, hasLength(1));
    expect(rows.first.id, created.id);
    expect(rows.first.originalText, '35块买菜');
  });

  test('duplicates are allowed and latest duplicate can be queried', () async {
    final first = await repository.create(_newTransaction());
    final candidateAfterFirst = await repository.findLatestDuplicateCandidate(
      _newTransaction(),
    );

    final second = await repository.create(_newTransaction());
    final candidateAfterSecond = await repository.findLatestDuplicateCandidate(
      _newTransaction(),
    );

    expect(candidateAfterFirst!.id, first.id);
    expect(candidateAfterSecond!.id, second.id);
    expect(await repository.list(), hasLength(2));
  });

  test('本月收支汇总不计入业务日之后的未来日期', () async {
    clock.set(DateTime.utc(2026, 8, 31, 10, 30));
    await repository.create(
      _newTransaction(amountCents: 3500, transactionDate: '2026-08-31'),
    );
    await db.insert(DatabaseSchema.transactionsTable, {
      'amount_cents': 1200,
      'type': 'expense',
      'category': 'groceries_food',
      'note': '未来支出',
      'original_text': '未来支出',
      'transaction_date': '2026-09-01',
      'created_at': '2026-08-31T10:00:00Z',
      'updated_at': '2026-08-31T10:00:00Z',
      'deleted_at': null,
    });
    await db.insert(DatabaseSchema.transactionsTable, {
      'amount_cents': 8000,
      'type': 'income',
      'category': 'salary',
      'note': '未来收入',
      'original_text': '未来收入',
      'transaction_date': '2026-09-01',
      'created_at': '2026-08-31T10:00:00Z',
      'updated_at': '2026-08-31T10:00:00Z',
      'deleted_at': null,
    });

    expect(await repository.monthExpenseCents(), 3500);
    expect(await repository.monthIncomeCents(), 0);
  });

  test('批量创建使用单个事务，全部成功后返回全部记录', () async {
    final created = await repository.createBatch([
      _newTransaction(amountCents: 1000, originalText: '买菜10元'),
      _newTransaction(
        amountCents: 2000,
        category: 'dining',
        note: '午饭',
        originalText: '午饭20元',
      ),
    ]);

    expect(created, hasLength(2));
    expect(created.map((entry) => entry.amountCents), [1000, 2000]);
    expect(await repository.list(), hasLength(2));
  });

  test('批量创建遇到非法记录时整批回滚', () async {
    await expectLater(
      repository.createBatch([
        _newTransaction(amountCents: 1000, originalText: '买菜10元'),
        _newTransaction(amountCents: 0, originalText: '无效账目'),
      ]),
      throwsA(isA<TransactionValidationException>()),
    );

    expect(await repository.list(), isEmpty);
  });

  test('deleted records cannot be edited before restore', () async {
    final created = await repository.create(_newTransaction());
    await repository.softDelete(created.id);

    await expectLater(
      repository.update(
        created.id,
        const LedgerTransactionUpdate(amountCents: 1800),
      ),
      throwsA(isA<TransactionValidationException>()),
    );
  });
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

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:smartledger/data/repositories/transaction_repository.dart';
import 'package:smartledger/data/sqlite/app_database.dart';
import 'package:smartledger/data/sqlite/database_schema.dart';
import 'package:smartledger/data/sqlite/transaction_local_data_source.dart';
import 'package:smartledger/domain/categories/category_catalog.dart';
import 'package:smartledger/domain/models/ledger_transaction.dart';
import 'package:smartledger/domain/models/transaction_type.dart';
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

  test('category catalog keeps frozen V1 codes by type', () {
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
        'other_expense',
      }),
    );
    expect(
      CategoryCatalog.forType(TransactionType.income)
          .map((category) => category.code)
          .toSet(),
      equals(<String>{'salary', 'other_income'}),
    );
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

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:smartledger/data/sqlite/app_database.dart';
import 'package:smartledger/data/sqlite/database_schema.dart';
import 'package:smartledger/data/sqlite/transaction_local_data_source.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  const newExpenseCategories = [
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
  ];
  const newIncomeCategories = [
    'bonus',
    'freelance',
    'business_income',
    'investment_income',
    'rental_income',
    'benefits_subsidies',
    'pension',
    'gift_red_envelope',
  ];

  late Directory tempDir;
  late Database db;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp(
      'smart_ledger_migration_test_',
    );
    db = await AppDatabase.openAtPath(
      path.join(tempDir.path, 'smart-ledger.sqlite'),
      databaseFactory: databaseFactoryFfi,
    );
  });

  tearDown(() async {
    await db.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('V4 支持全部新增支出分类，不允许收入分类做预算', () async {
    for (var index = 0; index < newExpenseCategories.length; index += 1) {
      final category = newExpenseCategories[index];
      await db.insert(DatabaseSchema.budgetsTable, {
        'category_code': category,
        'month': '2026-${(index + 1).toString().padLeft(2, '0')}',
        'amount_cents': 100,
        'enabled': 1,
        'created_at': '2026-09-01T00:00:00Z',
        'updated_at': '2026-09-01T00:00:00Z',
      });
      await db.insert(DatabaseSchema.transactionsTable, {
        'amount_cents': 100,
        'type': 'expense',
        'category': category,
        'note': null,
        'original_text': '新分类测试',
        'transaction_date': '2026-09-01',
        'created_at': '2026-09-01T00:00:00Z',
        'updated_at': '2026-09-01T00:00:00Z',
        'deleted_at': null,
      });
    }

    for (final category in newIncomeCategories) {
      await db.insert(DatabaseSchema.transactionsTable, {
        'amount_cents': 100,
        'type': 'income',
        'category': category,
        'note': null,
        'original_text': '新增收入分类测试',
        'transaction_date': '2026-09-01',
        'created_at': '2026-09-01T00:00:00Z',
        'updated_at': '2026-09-01T00:00:00Z',
        'deleted_at': null,
      });
    }

    await expectLater(
      db.insert(DatabaseSchema.budgetsTable, {
        'category_code': 'bonus',
        'month': '2027-01',
        'amount_cents': 100,
        'enabled': 1,
        'created_at': '2026-09-01T00:00:00Z',
        'updated_at': '2026-09-01T00:00:00Z',
      }),
      throwsA(isA<DatabaseException>()),
    );
  });

  test('V3 升级 V4 保持数据、索引、约束并重建分类触发器', () async {
    await db.close();
    final databasePath = path.join(tempDir.path, 'v3.sqlite');
    final v3 = await databaseFactoryFfi.openDatabase(
      databasePath,
      options: OpenDatabaseOptions(
        version: 3,
        onCreate: (database, _) async {
          await database.execute('''
CREATE TABLE transactions (
  id INTEGER PRIMARY KEY,
  amount_cents INTEGER NOT NULL CHECK (amount_cents > 0),
  type TEXT NOT NULL CHECK (type IN ('expense', 'income')),
  category TEXT NOT NULL,
  note TEXT,
  original_text TEXT NOT NULL,
  transaction_date TEXT NOT NULL,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  deleted_at TEXT
)
''');
          await database.execute(
            'CREATE INDEX idx_transactions_date_status ON transactions (transaction_date, deleted_at)',
          );
          await database.execute('''
CREATE TABLE budgets (
  id INTEGER PRIMARY KEY,
  category_code TEXT NOT NULL CHECK (category_code IN ('dining', 'other_expense')),
  month TEXT NOT NULL,
  amount_cents INTEGER NOT NULL,
  enabled INTEGER NOT NULL DEFAULT 1,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  UNIQUE(category_code, month)
)
''');
          await database.execute(
            'CREATE INDEX idx_budgets_month_enabled ON budgets (month, enabled)',
          );
          await database.execute('''
CREATE TRIGGER trg_transactions_type_category_insert
BEFORE INSERT ON transactions
FOR EACH ROW WHEN NEW.type = 'expense' AND NEW.category NOT IN ('dining', 'other_expense')
BEGIN SELECT RAISE(ABORT, 'category does not match type'); END
''');
          await database.execute('''
CREATE TRIGGER trg_transactions_type_category_update
BEFORE UPDATE OF type, category ON transactions
FOR EACH ROW WHEN NEW.type = 'expense' AND NEW.category NOT IN ('dining', 'other_expense')
BEGIN SELECT RAISE(ABORT, 'category does not match type'); END
''');
        },
      ),
    );
    await v3.insert('transactions', {
      'id': 7,
      'amount_cents': 3580,
      'type': 'expense',
      'category': 'dining',
      'note': '旧账目',
      'original_text': '旧账目',
      'transaction_date': '2026-09-01',
      'created_at': '2026-09-01T00:00:00Z',
      'updated_at': '2026-09-01T00:00:00Z',
      'deleted_at': '2026-09-02T00:00:00Z',
    });
    await v3.insert('budgets', {
      'id': 9,
      'category_code': 'dining',
      'month': '2026-09',
      'amount_cents': 5000,
      'enabled': 0,
      'created_at': '2026-09-01T00:00:00Z',
      'updated_at': '2026-09-01T00:00:00Z',
    });
    await v3.close();

    db = await AppDatabase.openAtPath(
      databasePath,
      databaseFactory: databaseFactoryFfi,
    );
    expect(await db.getVersion(), 4);
    expect((await db.query('transactions')).single['id'], 7);
    expect(
      (await db.query('transactions')).single['deleted_at'],
      '2026-09-02T00:00:00Z',
    );
    expect((await db.query('budgets')).single, containsPair('id', 9));
    expect((await db.query('budgets')).single, containsPair('enabled', 0));
    expect(
      (await db.rawQuery('PRAGMA index_list(budgets)'))
          .map((row) => row['name']),
      contains('idx_budgets_month_enabled'),
    );
    await db.insert('transactions', {
      'amount_cents': 100,
      'type': 'income',
      'category': 'bonus',
      'note': null,
      'original_text': '奖金',
      'transaction_date': '2026-09-03',
      'created_at': '2026-09-03T00:00:00Z',
      'updated_at': '2026-09-03T00:00:00Z',
      'deleted_at': null,
    });
  });

  test('空数据库直接创建 V2.6 schema', () async {
    expect(await db.getVersion(), DatabaseSchema.version);
    expect(
      await db.rawQuery('PRAGMA table_info(${DatabaseSchema.budgetsTable})'),
      hasLength(7),
    );
    expect(
      await db.rawQuery(
        'PRAGMA table_info(${DatabaseSchema.transactionsTable})',
      ),
      hasLength(10),
    );
    expect(
      (await db.rawQuery('PRAGMA index_list(${DatabaseSchema.budgetsTable})'))
          .map((row) => row['name']),
      contains('idx_budgets_month_enabled'),
    );
    expect(
      await db.rawQuery(
        'PRAGMA table_info(${DatabaseSchema.importBatchesTable})',
      ),
      hasLength(6),
    );
  });

  test('V1 数据库升级后 transactions 完整可读且不被重建', () async {
    await db.close();
    final databasePath = path.join(tempDir.path, 'v1.sqlite');
    final v1 = await databaseFactoryFfi.openDatabase(
      databasePath,
      options: OpenDatabaseOptions(
        version: 1,
        onConfigure: (database) async {
          await database.execute('PRAGMA foreign_keys = ON');
        },
        onCreate: (database, _) async {
          await database.execute('''
CREATE TABLE transactions (
  id INTEGER PRIMARY KEY,
  amount_cents INTEGER NOT NULL CHECK (amount_cents > 0),
  type TEXT NOT NULL CHECK (type IN ('expense', 'income')),
  category TEXT NOT NULL,
  note TEXT CHECK (note IS NULL OR length(note) <= 200),
  original_text TEXT NOT NULL
    CHECK (length(trim(original_text)) >= 1 AND length(original_text) <= 500),
  transaction_date TEXT NOT NULL,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  deleted_at TEXT
)
''');
          await database.execute('''
CREATE INDEX idx_transactions_date_status
ON transactions (transaction_date, deleted_at)
''');
        },
      ),
    );
    final originalExpenseId = await v1.insert('transactions', {
      'amount_cents': 3580,
      'type': 'expense',
      'category': 'groceries_food',
      'note': '买菜',
      'original_text': '35.80元买菜',
      'transaction_date': '2026-08-31',
      'created_at': '2026-08-31T10:00:00Z',
      'updated_at': '2026-08-31T10:00:00Z',
      'deleted_at': null,
    });
    final originalIncomeId = await v1.insert('transactions', {
      'amount_cents': 92000,
      'type': 'income',
      'category': 'salary',
      'note': null,
      'original_text': '工资到账920元',
      'transaction_date': '2026-08-30',
      'created_at': '2026-08-30T09:00:00Z',
      'updated_at': '2026-08-30T09:05:00Z',
      'deleted_at': null,
    });
    final originalDeletedId = await v1.insert('transactions', {
      'amount_cents': 1200,
      'type': 'expense',
      'category': 'dining',
      'note': '已撤销',
      'original_text': '已撤销餐饮12元',
      'transaction_date': '2026-08-29',
      'created_at': '2026-08-29T08:00:00Z',
      'updated_at': '2026-08-29T08:30:00Z',
      'deleted_at': '2026-08-29T08:30:00Z',
    });
    final v1TransactionColumns = await v1.rawQuery(
      'PRAGMA table_info(transactions)',
    );
    final v1Rows = await v1.query('transactions', orderBy: 'id ASC');
    await v1.close();

    db = await AppDatabase.openAtPath(
      databasePath,
      databaseFactory: databaseFactoryFfi,
    );
    final dataSource = TransactionLocalDataSource(db);
    final restoredExpense = await dataSource.findById(originalExpenseId);
    final restoredIncome = await dataSource.findById(originalIncomeId);
    final restoredDeleted = await dataSource.findById(
      originalDeletedId,
      includeDeleted: true,
    );

    expect(await db.getVersion(), DatabaseSchema.version);
    expect(restoredExpense, isNotNull);
    expect(restoredExpense!.amountCents, 3580);
    expect(restoredExpense.category, 'groceries_food');
    expect(restoredExpense.note, '买菜');
    expect(restoredExpense.originalText, '35.80元买菜');
    expect(restoredIncome, isNotNull);
    expect(restoredIncome!.type.code, 'income');
    expect(restoredIncome.amountCents, 92000);
    expect(restoredIncome.note, isNull);
    expect(restoredDeleted, isNotNull);
    expect(restoredDeleted!.isDeleted, isTrue);
    expect(restoredDeleted.deletedAt, DateTime.parse('2026-08-29T08:30:00Z'));
    expect(
      await db.rawQuery(
        'PRAGMA table_info(${DatabaseSchema.transactionsTable})',
      ),
      v1TransactionColumns,
    );
    expect(
      await db.query(DatabaseSchema.transactionsTable, orderBy: 'id ASC'),
      v1Rows,
    );
    expect(await db.query(DatabaseSchema.budgetsTable), isEmpty);
    expect(await db.query(DatabaseSchema.importBatchesTable), isEmpty);
  });

  test('budgets 表约束正整数分、支出分类、月份和唯一性', () async {
    final base = <String, Object?>{
      'category_code': 'dining',
      'month': '2026-09',
      'amount_cents': 100,
      'enabled': 1,
      'created_at': '2026-09-01T00:00:00Z',
      'updated_at': '2026-09-01T00:00:00Z',
    };
    await db.insert(DatabaseSchema.budgetsTable, base);

    await expectLater(
      db.insert(DatabaseSchema.budgetsTable, {
        ...base,
        'category_code': 'salary',
        'month': '2026-10',
      }),
      throwsA(isA<DatabaseException>()),
    );
    await expectLater(
      db.insert(DatabaseSchema.budgetsTable, {...base, 'month': '2026-13'}),
      throwsA(isA<DatabaseException>()),
    );
    await expectLater(
      db.insert(DatabaseSchema.budgetsTable, {
        ...base,
        'month': '2026-11',
        'amount_cents': 0,
      }),
      throwsA(isA<DatabaseException>()),
    );
    await expectLater(
      db.insert(DatabaseSchema.budgetsTable, {...base, 'month': '0000-09'}),
      throwsA(isA<DatabaseException>()),
    );
    await expectLater(
      db.insert(DatabaseSchema.budgetsTable, base),
      throwsA(isA<DatabaseException>()),
    );
  });

  test('V3 升级到 V4 保留数据、索引、唯一约束并启用新增固定分类', () async {
    await db.close();
    final databasePath = path.join(tempDir.path, 'v3.sqlite');
    final v3 = await databaseFactoryFfi.openDatabase(
      databasePath,
      options: OpenDatabaseOptions(
        version: 3,
        onConfigure: (database) async {
          await database.execute('PRAGMA foreign_keys = ON');
        },
        onCreate: (database, _) async {
          await database.execute('''
CREATE TABLE transactions (
  id INTEGER PRIMARY KEY,
  amount_cents INTEGER NOT NULL CHECK (amount_cents > 0),
  type TEXT NOT NULL CHECK (type IN ('expense', 'income')),
  category TEXT NOT NULL,
  note TEXT CHECK (note IS NULL OR length(note) <= 200),
  original_text TEXT NOT NULL,
  transaction_date TEXT NOT NULL,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  deleted_at TEXT
)
''');
          await database.execute('''
CREATE INDEX idx_transactions_date_status
ON transactions (transaction_date, deleted_at)
''');
          await database.execute('''
CREATE TABLE budgets (
  id INTEGER PRIMARY KEY,
  category_code TEXT NOT NULL CHECK (category_code IN (
    'dining', 'groceries_food', 'daily_necessities', 'transportation',
    'vehicle_fuel', 'housing', 'communication', 'entertainment',
    'children', 'medical', 'other_expense'
  )),
  month TEXT NOT NULL,
  amount_cents INTEGER NOT NULL,
  enabled INTEGER NOT NULL DEFAULT 1,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  UNIQUE(category_code, month)
)
''');
          await database.execute('''
CREATE INDEX idx_budgets_month_enabled
ON budgets (month, enabled)
''');
          await database.execute('''
CREATE TRIGGER trg_transactions_type_category_insert
BEFORE INSERT ON transactions
FOR EACH ROW
WHEN NEW.type = 'expense' AND NEW.category NOT IN ('dining')
BEGIN
  SELECT RAISE(ABORT, 'category does not match type');
END
''');
          await database.execute('''
CREATE TRIGGER trg_transactions_type_category_update
BEFORE UPDATE OF type, category ON transactions
FOR EACH ROW
WHEN NEW.type = 'expense' AND NEW.category NOT IN ('dining')
BEGIN
  SELECT RAISE(ABORT, 'category does not match type');
END
''');
          await database.execute('''
CREATE TRIGGER trg_transactions_amount_integer_insert
BEFORE INSERT ON transactions
FOR EACH ROW
WHEN NEW.amount_cents <= 0
BEGIN
  SELECT RAISE(ABORT, 'amount_cents must be positive');
END
''');
          await database.execute('''
CREATE TRIGGER trg_transactions_amount_integer_update
BEFORE UPDATE OF amount_cents ON transactions
FOR EACH ROW
WHEN NEW.amount_cents <= 0
BEGIN
  SELECT RAISE(ABORT, 'amount_cents must be positive');
END
''');
        },
      ),
    );
    await v3.insert('transactions', {
      'id': 7,
      'amount_cents': 2580,
      'type': 'expense',
      'category': 'dining',
      'note': '旧账目',
      'original_text': '旧餐饮账目',
      'transaction_date': '2026-08-31',
      'created_at': '2026-08-31T10:00:00Z',
      'updated_at': '2026-08-31T10:00:00Z',
      'deleted_at': '2026-09-01T10:00:00Z',
    });
    await v3.insert('budgets', {
      'id': 9,
      'category_code': 'dining',
      'month': '2026-09',
      'amount_cents': 50000,
      'enabled': 0,
      'created_at': '2026-09-01T00:00:00Z',
      'updated_at': '2026-09-02T00:00:00Z',
    });
    await v3.close();

    db = await AppDatabase.openAtPath(
      databasePath,
      databaseFactory: databaseFactoryFfi,
    );

    expect(await db.getVersion(), DatabaseSchema.version);
    expect(await db.query('transactions'), contains(containsPair('id', 7)));
    expect(
      await db.query('budgets'),
      contains(
        allOf(
          containsPair('id', 9),
          containsPair('amount_cents', 50000),
          containsPair('month', '2026-09'),
          containsPair('enabled', 0),
        ),
      ),
    );
    expect(
      (await db.rawQuery('PRAGMA index_list(budgets)'))
          .map((row) => row['name']),
      contains('idx_budgets_month_enabled'),
    );

    await db.insert('budgets', {
      'category_code': 'clothing_beauty',
      'month': '2026-10',
      'amount_cents': 10000,
      'enabled': 1,
      'created_at': '2026-09-01T00:00:00Z',
      'updated_at': '2026-09-01T00:00:00Z',
    });
    await expectLater(
      db.insert('budgets', {
        'category_code': 'dining',
        'month': '2026-09',
        'amount_cents': 1,
        'enabled': 1,
        'created_at': '2026-09-01T00:00:00Z',
        'updated_at': '2026-09-01T00:00:00Z',
      }),
      throwsA(isA<DatabaseException>()),
    );

    await db.insert('transactions', {
      'amount_cents': 1200,
      'type': 'expense',
      'category': 'clothing_beauty',
      'note': null,
      'original_text': '买衣服',
      'transaction_date': '2026-09-05',
      'created_at': '2026-09-05T00:00:00Z',
      'updated_at': '2026-09-05T00:00:00Z',
      'deleted_at': null,
    });
    await expectLater(
      db.insert('transactions', {
        'amount_cents': 1200.5,
        'type': 'expense',
        'category': 'dining',
        'note': null,
        'original_text': '小数分',
        'transaction_date': '2026-09-05',
        'created_at': '2026-09-05T00:00:00Z',
        'updated_at': '2026-09-05T00:00:00Z',
        'deleted_at': null,
      }),
      throwsA(isA<DatabaseException>()),
    );
    await expectLater(
      db.insert('transactions', {
        'amount_cents': 1200,
        'type': 'expense',
        'category': 'not_a_category',
        'note': null,
        'original_text': '未知分类',
        'transaction_date': '2026-09-05',
        'created_at': '2026-09-05T00:00:00Z',
        'updated_at': '2026-09-05T00:00:00Z',
        'deleted_at': null,
      }),
      throwsA(isA<DatabaseException>()),
    );
  });

  test('transactions 表通过触发器强制金额为整数且分类匹配收支', () async {
    final base = <String, Object?>{
      'amount_cents': 100,
      'type': 'expense',
      'category': 'dining',
      'note': null,
      'original_text': '测试账目',
      'transaction_date': '2026-08-31',
      'created_at': '2026-08-31T00:00:00Z',
      'updated_at': '2026-08-31T00:00:00Z',
      'deleted_at': null,
    };

    await expectLater(
      db.insert(DatabaseSchema.transactionsTable, {
        ...base,
        'amount_cents': 1.5,
      }),
      throwsA(isA<DatabaseException>()),
    );
    await expectLater(
      db.insert(DatabaseSchema.transactionsTable, {
        ...base,
        'type': 'income',
        'category': 'dining',
      }),
      throwsA(isA<DatabaseException>()),
    );

    final id = await db.insert(DatabaseSchema.transactionsTable, base);
    await expectLater(
      db.update(
        DatabaseSchema.transactionsTable,
        {'amount_cents': 2.5},
        where: 'id = ?',
        whereArgs: [id],
      ),
      throwsA(isA<DatabaseException>()),
    );
  });

  test('旧库中的整数型 REAL 金额会迁移为整数分', () async {
    await db.close();
    final databasePath = path.join(tempDir.path, 'v1-real.sqlite');
    final v1 = await databaseFactoryFfi.openDatabase(
      databasePath,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (database, _) async {
          await database.execute('''
CREATE TABLE transactions (
  id INTEGER PRIMARY KEY,
  amount_cents REAL NOT NULL CHECK (amount_cents > 0),
  type TEXT NOT NULL CHECK (type IN ('expense', 'income')),
  category TEXT NOT NULL,
  note TEXT,
  original_text TEXT NOT NULL,
  transaction_date TEXT NOT NULL,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  deleted_at TEXT
)
''');
        },
      ),
    );
    await v1.insert('transactions', {
      'amount_cents': 3580.0,
      'type': 'expense',
      'category': 'groceries_food',
      'note': '买菜',
      'original_text': '35.80元买菜',
      'transaction_date': '2026-08-31',
      'created_at': '2026-08-31T10:00:00Z',
      'updated_at': '2026-08-31T10:00:00Z',
      'deleted_at': null,
    });
    await v1.close();

    db = await AppDatabase.openAtPath(
      databasePath,
      databaseFactory: databaseFactoryFfi,
    );
    final row = (await db.query('transactions')).single;
    final dataSource = TransactionLocalDataSource(db);
    final restored = (await dataSource.listAllForBackup()).single;

    expect(row['amount_cents'], 3580.0);
    expect(restored.amountCents, 3580);
  });

  test('旧库中的小数分金额拒绝升级而不是静默取整', () async {
    await db.close();
    final databasePath = path.join(tempDir.path, 'v1-fractional.sqlite');
    final v1 = await databaseFactoryFfi.openDatabase(
      databasePath,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (database, _) async {
          await database.execute('''
CREATE TABLE transactions (
  id INTEGER PRIMARY KEY,
  amount_cents REAL NOT NULL CHECK (amount_cents > 0),
  type TEXT NOT NULL CHECK (type IN ('expense', 'income')),
  category TEXT NOT NULL,
  note TEXT,
  original_text TEXT NOT NULL,
  transaction_date TEXT NOT NULL,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  deleted_at TEXT
)
''');
        },
      ),
    );
    await v1.insert('transactions', {
      'amount_cents': 3580.5,
      'type': 'expense',
      'category': 'groceries_food',
      'note': '买菜',
      'original_text': '金额异常',
      'transaction_date': '2026-08-31',
      'created_at': '2026-08-31T10:00:00Z',
      'updated_at': '2026-08-31T10:00:00Z',
      'deleted_at': null,
    });
    await v1.close();

    await expectLater(
      AppDatabase.openAtPath(databasePath, databaseFactory: databaseFactoryFfi),
      throwsA(isA<StateError>()),
    );
  });

  test('旧库未知分类迁移为按收支类型的其他分类并保留原分类线索', () async {
    await db.close();
    final databasePath = path.join(tempDir.path, 'v1-unknown-category.sqlite');
    final v1 = await databaseFactoryFfi.openDatabase(
      databasePath,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (database, _) async {
          await database.execute('''
CREATE TABLE transactions (
  id INTEGER PRIMARY KEY,
  amount_cents INTEGER NOT NULL CHECK (amount_cents > 0),
  type TEXT NOT NULL CHECK (type IN ('expense', 'income')),
  category TEXT NOT NULL,
  note TEXT,
  original_text TEXT NOT NULL,
  transaction_date TEXT NOT NULL,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  deleted_at TEXT
)
''');
        },
      ),
    );
    await v1.insert('transactions', {
      'amount_cents': 1200,
      'type': 'expense',
      'category': 'legacy_unknown',
      'note': '旧备注',
      'original_text': '旧分类账目12元',
      'transaction_date': '2026-08-31',
      'created_at': '2026-08-31T10:00:00Z',
      'updated_at': '2026-08-31T10:00:00Z',
      'deleted_at': null,
    });
    await v1.close();

    db = await AppDatabase.openAtPath(
      databasePath,
      databaseFactory: databaseFactoryFfi,
    );
    final dataSource = TransactionLocalDataSource(db);
    final restored = (await dataSource.listAllForBackup()).single;

    expect(restored.category, 'other_expense');
    expect(restored.note, contains('原分类：legacy_unknown'));
    expect(restored.note, contains('旧备注'));
  });
}

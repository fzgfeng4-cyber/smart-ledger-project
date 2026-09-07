import 'package:sqflite/sqflite.dart';

final class DatabaseSchema {
  const DatabaseSchema._();

  static const version = 4;
  static const maxSqliteInteger = 9223372036854775807;
  static const transactionsTable = 'transactions';
  static const budgetsTable = 'budgets';
  static const importBatchesTable = 'import_batches';

  static Future<void> configure(Database db) async {
    await db.execute('PRAGMA foreign_keys = ON');
  }

  static Future<void> onCreate(Database db, int version) async {
    await _runMigrations(db, fromVersion: 0, toVersion: version);
  }

  static Future<void> onUpgrade(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    await _runMigrations(db, fromVersion: oldVersion, toVersion: newVersion);
  }

  static Future<void> onOpen(Database db) async {
    await _ensureIntegrityTriggers(db);
  }

  static Future<void> onDowngrade(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    throw StateError('不支持数据库降级: $oldVersion -> $newVersion');
  }

  static Future<void> _runMigrations(
    Database db, {
    required int fromVersion,
    required int toVersion,
  }) async {
    for (
      var nextVersion = fromVersion + 1;
      nextVersion <= toVersion;
      nextVersion += 1
    ) {
      switch (nextVersion) {
        case 1:
          await _createV1(db);
        case 2:
          await _migrateV1Transactions(db);
          await _createV2(db);
        case 3:
          await _createV3(db);
        case 4:
          await _migrateV3ToV4(db);
        default:
          throw StateError('缺少数据库迁移版本: $nextVersion');
      }
    }
    await _ensureIntegrityTriggers(db);
  }

  static Future<void> _createV1(Database db) async {
    await db.execute('''
CREATE TABLE $transactionsTable (
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

    await db.execute('''
CREATE INDEX idx_transactions_date_status
ON $transactionsTable (transaction_date, deleted_at)
''');
  }

  static Future<void> _createV2(Database db) async {
    await db.execute('''
CREATE TABLE $budgetsTable (
  id INTEGER PRIMARY KEY,
  category_code TEXT NOT NULL CHECK (
    category_code IN (
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
      'charity_donation'
    )
  ),
  month TEXT NOT NULL CHECK (
    typeof(month) = 'text'
    AND length(month) = 7
    AND month GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]'
    AND substr(month, 1, 4) != '0000'
    AND substr(month, 6, 2) BETWEEN '01' AND '12'
  ),
  amount_cents INTEGER NOT NULL CHECK (
    typeof(amount_cents) = 'integer' AND amount_cents > 0
  ),
  enabled INTEGER NOT NULL DEFAULT 1 CHECK (
    typeof(enabled) = 'integer' AND enabled IN (0, 1)
  ),
  created_at TEXT NOT NULL CHECK (
    typeof(created_at) = 'text' AND length(trim(created_at)) > 0
  ),
  updated_at TEXT NOT NULL CHECK (
    typeof(updated_at) = 'text' AND length(trim(updated_at)) > 0
  ),
  UNIQUE(category_code, month)
)
''');

    await db.execute('''
CREATE INDEX idx_budgets_month_enabled
ON $budgetsTable (month, enabled)
''');
  }

  static Future<void> _createV3(Database db) async {
    await db.execute('''
CREATE TABLE $importBatchesTable (
  id INTEGER PRIMARY KEY,
  source TEXT NOT NULL CHECK (
    source IN ('wechat_csv', 'alipay_csv')
  ),
  fingerprint TEXT NOT NULL CHECK (
    typeof(fingerprint) = 'text'
    AND length(trim(fingerprint)) > 0
    AND length(fingerprint) <= 200
  ),
  file_name TEXT NOT NULL CHECK (
    typeof(file_name) = 'text'
    AND length(trim(file_name)) > 0
    AND length(file_name) <= 200
  ),
  transaction_count INTEGER NOT NULL CHECK (
    typeof(transaction_count) = 'integer'
    AND transaction_count > 0
  ),
  imported_at TEXT NOT NULL CHECK (
    typeof(imported_at) = 'text'
    AND length(trim(imported_at)) > 0
  ),
  UNIQUE(source, fingerprint)
)
''');

    await db.execute('''
CREATE INDEX idx_import_batches_imported_at
ON $importBatchesTable (imported_at DESC, id DESC)
''');
  }

  static Future<void> _migrateV3ToV4(Database db) async {
    await _dropTransactionCategoryTriggers(db);

    const legacyBudgetsTable = 'budgets_v3_legacy';
    try {
      await db.execute('DROP INDEX IF EXISTS idx_budgets_month_enabled');
      await db.execute(
        'ALTER TABLE $budgetsTable RENAME TO $legacyBudgetsTable',
      );
      await _createV4Budgets(db);
      await db.execute('''
INSERT INTO $budgetsTable (
  id, category_code, month, amount_cents, enabled, created_at, updated_at
)
SELECT id, category_code, month, amount_cents, enabled, created_at, updated_at
FROM $legacyBudgetsTable
''');
      await db.execute('DROP TABLE $legacyBudgetsTable');
      await db.execute('''
CREATE INDEX idx_budgets_month_enabled
ON $budgetsTable (month, enabled)
''');
    } on Object catch (error) {
      throw StateError('V3 到 V4 预算表迁移失败，原有预算数据未被静默丢弃: $error');
    }
  }

  static Future<void> _createV4Budgets(Database db) async {
    await db.execute('''
CREATE TABLE $budgetsTable (
  id INTEGER PRIMARY KEY,
  category_code TEXT NOT NULL CHECK (
    category_code IN (
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
      'charity_donation'
    )
  ),
  month TEXT NOT NULL CHECK (
    typeof(month) = 'text'
    AND length(month) = 7
    AND month GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]'
    AND substr(month, 1, 4) != '0000'
    AND substr(month, 6, 2) BETWEEN '01' AND '12'
  ),
  amount_cents INTEGER NOT NULL CHECK (
    typeof(amount_cents) = 'integer' AND amount_cents > 0
  ),
  enabled INTEGER NOT NULL DEFAULT 1 CHECK (
    typeof(enabled) = 'integer' AND enabled IN (0, 1)
  ),
  created_at TEXT NOT NULL CHECK (
    typeof(created_at) = 'text' AND length(trim(created_at)) > 0
  ),
  updated_at TEXT NOT NULL CHECK (
    typeof(updated_at) = 'text' AND length(trim(updated_at)) > 0
  ),
  UNIQUE(category_code, month)
)
''');
  }

  static Future<void> _migrateV1Transactions(Database db) async {
    final rows = await db.query(
      transactionsTable,
      columns: const ['id', 'amount_cents', 'type', 'category', 'note'],
    );

    for (final row in rows) {
      final id = row['id'];
      if (id is! int || id <= 0) {
        throw StateError('旧账目 id 无效，无法完成数据库迁移');
      }

      final amount = row['amount_cents'];
      final normalizedAmount = _normalizeLegacyAmount(amount, id);
      final type = row['type'];
      if (type is! String || (type != 'expense' && type != 'income')) {
        throw StateError('旧账目 #$id 收支类型无效，无法完成数据库迁移');
      }

      final category = row['category'];
      if (category is! String || category.trim().isEmpty) {
        throw StateError('旧账目 #$id 分类为空，无法完成数据库迁移');
      }

      final values = <String, Object?>{};
      if (amount is! int || amount != normalizedAmount) {
        values['amount_cents'] = normalizedAmount;
      }

      if (!_isCategoryValidForType(type, category)) {
        values['category'] = type == 'income'
            ? 'other_income'
            : 'other_expense';
        values['note'] = _appendLegacyCategory(
          row['note'] as String?,
          category,
          id,
        );
      }

      if (values.isNotEmpty) {
        await db.update(
          transactionsTable,
          values,
          where: 'id = ?',
          whereArgs: [id],
        );
      }
    }
  }

  static int _normalizeLegacyAmount(Object? value, int id) {
    if (value is int) {
      if (value <= 0) {
        throw StateError('旧账目 #$id 金额必须是正整数分');
      }
      return value;
    }
    if (value is double &&
        value.isFinite &&
        value == value.truncateToDouble() &&
        value > 0 &&
        value <= maxSqliteInteger) {
      return value.toInt();
    }
    throw StateError('旧账目 #$id 金额不是可安全转换的整数分');
  }

  static String _appendLegacyCategory(String? note, String category, int id) {
    final suffix = '原分类：${category.trim()}';
    final normalizedNote = note?.trim();
    final combined = normalizedNote == null || normalizedNote.isEmpty
        ? suffix
        : '$normalizedNote · $suffix';
    if (combined.length > 200) {
      throw StateError('旧账目 #$id 的备注无法容纳原分类，拒绝静默丢失数据');
    }
    return combined;
  }

  static bool _isCategoryValidForType(String type, String category) {
    final expenseCategories = <String>{
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
    };
    final incomeCategories = <String>{
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
    };
    return type == 'expense'
        ? expenseCategories.contains(category.trim())
        : incomeCategories.contains(category.trim());
  }

  static Future<void> _ensureIntegrityTriggers(Database db) async {
    await _dropTransactionCategoryTriggers(db);
    await _validateExistingTransactionRows(db);

    await db.execute('''
CREATE TRIGGER IF NOT EXISTS trg_transactions_amount_integer_insert
BEFORE INSERT ON $transactionsTable
FOR EACH ROW
WHEN
  NEW.amount_cents IS NULL
  OR NEW.amount_cents <= 0
  OR (
    typeof(NEW.amount_cents) <> 'integer'
    AND NOT (
      typeof(NEW.amount_cents) = 'real'
      AND NEW.amount_cents = CAST(NEW.amount_cents AS INTEGER)
      AND NEW.amount_cents <= $maxSqliteInteger
    )
  )
BEGIN
  SELECT RAISE(ABORT, 'amount_cents must be a positive integer value');
END
''');

    await db.execute('''
CREATE TRIGGER IF NOT EXISTS trg_transactions_amount_integer_update
BEFORE UPDATE OF amount_cents ON $transactionsTable
FOR EACH ROW
WHEN
  NEW.amount_cents IS NULL
  OR NEW.amount_cents <= 0
  OR (
    typeof(NEW.amount_cents) <> 'integer'
    AND NOT (
      typeof(NEW.amount_cents) = 'real'
      AND NEW.amount_cents = CAST(NEW.amount_cents AS INTEGER)
      AND NEW.amount_cents <= $maxSqliteInteger
    )
  )
BEGIN
  SELECT RAISE(ABORT, 'amount_cents must be a positive integer value');
END
''');

    await db.execute('''
    CREATE TRIGGER IF NOT EXISTS trg_transactions_type_category_insert
BEFORE INSERT ON $transactionsTable
FOR EACH ROW
WHEN
  (NEW.type = 'expense' AND NEW.category NOT IN (
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
    'other_expense'
  ))
  OR
  (NEW.type = 'income' AND NEW.category NOT IN (
    'salary',
    'bonus',
    'freelance',
    'business_income',
    'investment_income',
    'rental_income',
    'benefits_subsidies',
    'pension',
    'gift_red_envelope',
    'other_income'
  ))
BEGIN
  SELECT RAISE(ABORT, 'category does not match type');
END
''');

    await db.execute('''
CREATE TRIGGER IF NOT EXISTS trg_transactions_type_category_update
BEFORE UPDATE OF type, category ON $transactionsTable
FOR EACH ROW
WHEN
  (NEW.type = 'expense' AND NEW.category NOT IN (
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
    'other_expense'
  ))
  OR
  (NEW.type = 'income' AND NEW.category NOT IN (
    'salary',
    'bonus',
    'freelance',
    'business_income',
    'investment_income',
    'rental_income',
    'benefits_subsidies',
    'pension',
    'gift_red_envelope',
    'other_income'
  ))
BEGIN
  SELECT RAISE(ABORT, 'category does not match type');
END
''');
  }

  static Future<void> _validateExistingTransactionRows(Database db) async {
    final invalidAmountRows = await db.rawQuery('''
SELECT id
FROM $transactionsTable
WHERE
  amount_cents IS NULL
  OR amount_cents <= 0
  OR (
    typeof(amount_cents) <> 'integer'
    AND NOT (
      typeof(amount_cents) = 'real'
      AND amount_cents = CAST(amount_cents AS INTEGER)
      AND amount_cents <= $maxSqliteInteger
    )
  )
LIMIT 1
''');
    if (invalidAmountRows.isNotEmpty) {
      throw StateError('transactions.amount_cents 存在非正整数数据');
    }

    final invalidCategoryRows = await db.rawQuery('''
SELECT id
FROM $transactionsTable
WHERE
  (type = 'expense' AND category NOT IN (
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
      'other_expense'
  ))
  OR
  (type = 'income' AND category NOT IN (
    'salary',
    'bonus',
    'freelance',
    'business_income',
    'investment_income',
    'rental_income',
    'benefits_subsidies',
    'pension',
    'gift_red_envelope',
    'other_income'
  ))
LIMIT 1
''');
    if (invalidCategoryRows.isNotEmpty) {
      throw StateError('transactions.type 与 category 存在不一致数据');
    }
  }

  static Future<void> _dropTransactionCategoryTriggers(Database db) async {
    await db.execute(
      'DROP TRIGGER IF EXISTS trg_transactions_amount_integer_insert',
    );
    await db.execute(
      'DROP TRIGGER IF EXISTS trg_transactions_amount_integer_update',
    );
    await db.execute(
      'DROP TRIGGER IF EXISTS trg_transactions_type_category_insert',
    );
    await db.execute(
      'DROP TRIGGER IF EXISTS trg_transactions_type_category_update',
    );
  }
}

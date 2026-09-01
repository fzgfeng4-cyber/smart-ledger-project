import 'package:sqflite/sqflite.dart';

final class DatabaseSchema {
  const DatabaseSchema._();

  static const version = 1;
  static const transactionsTable = 'transactions';

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
        default:
          throw StateError('缺少数据库迁移版本: $nextVersion');
      }
    }
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
}

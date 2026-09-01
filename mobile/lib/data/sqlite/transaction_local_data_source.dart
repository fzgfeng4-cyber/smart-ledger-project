import 'package:sqflite/sqflite.dart';

import '../../domain/models/ledger_transaction.dart';
import '../../domain/models/transaction_type.dart';
import '../../shared/clock.dart';
import 'database_schema.dart';

final class TransactionLocalDataSource {
  const TransactionLocalDataSource(this._db);

  final Database _db;

  Future<LedgerTransaction> insert(
    NewLedgerTransaction transaction, {
    required DateTime now,
  }) async {
    final timestamp = formatUtcIsoSeconds(now);
    final id = await _db.insert(DatabaseSchema.transactionsTable, {
      'amount_cents': transaction.amountCents,
      'type': transaction.type.code,
      'category': transaction.category,
      'note': transaction.note,
      'original_text': transaction.originalText,
      'transaction_date': transaction.transactionDate,
      'created_at': timestamp,
      'updated_at': timestamp,
      'deleted_at': null,
    }, conflictAlgorithm: ConflictAlgorithm.abort);

    final created = await findById(id, includeDeleted: true);
    if (created == null) {
      throw StateError('新增账目后无法读取记录');
    }
    return created;
  }

  Future<LedgerTransaction?> findById(
    int id, {
    bool includeDeleted = false,
  }) async {
    final rows = await _db.query(
      DatabaseSchema.transactionsTable,
      where: includeDeleted ? 'id = ?' : 'id = ? AND deleted_at IS NULL',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return LedgerTransaction.fromMap(rows.first);
  }

  Future<LedgerTransaction?> update(
    int id,
    LedgerTransactionUpdate update, {
    required DateTime now,
  }) async {
    if (!update.hasChanges) {
      return findById(id);
    }

    final values = <String, Object?>{'updated_at': formatUtcIsoSeconds(now)};

    final amountCents = update.amountCents;
    if (amountCents != null) {
      values['amount_cents'] = amountCents;
    }

    final type = update.type;
    if (type != null) {
      values['type'] = type.code;
    }

    final category = update.category;
    if (category != null) {
      values['category'] = category;
    }

    if (update.hasNote) {
      values['note'] = update.note;
    }

    final transactionDate = update.transactionDate;
    if (transactionDate != null) {
      values['transaction_date'] = transactionDate;
    }

    final count = await _db.update(
      DatabaseSchema.transactionsTable,
      values,
      where: 'id = ? AND deleted_at IS NULL',
      whereArgs: [id],
    );

    if (count == 0) {
      return null;
    }
    return findById(id);
  }

  Future<LedgerTransaction?> softDelete(int id, {required DateTime now}) async {
    final timestamp = formatUtcIsoSeconds(now);
    final count = await _db.update(
      DatabaseSchema.transactionsTable,
      {'deleted_at': timestamp, 'updated_at': timestamp},
      where: 'id = ? AND deleted_at IS NULL',
      whereArgs: [id],
    );

    if (count == 0) {
      return null;
    }
    return findById(id, includeDeleted: true);
  }

  Future<LedgerTransaction?> restore(int id, {required DateTime now}) async {
    final count = await _db.update(
      DatabaseSchema.transactionsTable,
      {'deleted_at': null, 'updated_at': formatUtcIsoSeconds(now)},
      where: 'id = ? AND deleted_at IS NOT NULL',
      whereArgs: [id],
    );

    if (count == 0) {
      return null;
    }
    return findById(id);
  }

  Future<List<LedgerTransaction>> listActive({
    required int limit,
    required int offset,
  }) async {
    final rows = await _db.query(
      DatabaseSchema.transactionsTable,
      where: 'deleted_at IS NULL',
      orderBy: 'transaction_date DESC, updated_at DESC, id DESC',
      limit: limit,
      offset: offset,
    );
    return rows.map(LedgerTransaction.fromMap).toList();
  }

  Future<List<LedgerTransaction>> listAllForBackup() async {
    final rows = await _db.query(
      DatabaseSchema.transactionsTable,
      orderBy: 'id ASC',
    );
    return rows.map(LedgerTransaction.fromMap).toList();
  }

  Future<void> replaceAllForBackup(
    Iterable<LedgerTransaction> transactions,
  ) async {
    await _db.transaction((transaction) async {
      await transaction.delete(DatabaseSchema.transactionsTable);
      for (final entry in transactions) {
        await transaction.insert(
          DatabaseSchema.transactionsTable,
          entry.toMap(),
          conflictAlgorithm: ConflictAlgorithm.abort,
        );
      }
    });
  }

  Future<LedgerTransaction?> findLatestMatchingActive({
    required int amountCents,
    required TransactionType type,
    required String category,
    required String? note,
    required String transactionDate,
  }) async {
    final rows = await _db.query(
      DatabaseSchema.transactionsTable,
      where:
          '''
deleted_at IS NULL
AND transaction_date = ?
AND amount_cents = ?
AND type = ?
AND category = ?
AND ${note == null ? 'note IS NULL' : 'note = ?'}
''',
      whereArgs: [transactionDate, amountCents, type.code, category, ?note],
      orderBy: 'transaction_date DESC, updated_at DESC, id DESC',
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return LedgerTransaction.fromMap(rows.first);
  }

  Future<int> sumActiveByTypeOnDate({
    required TransactionType type,
    required String date,
  }) {
    return _sum(
      where: 'deleted_at IS NULL AND type = ? AND transaction_date = ?',
      whereArgs: [type.code, date],
    );
  }

  Future<int> sumActiveByTypeInDateRange({
    required TransactionType type,
    required String startDateInclusive,
    required String endDateExclusive,
  }) {
    return _sum(
      where: '''
deleted_at IS NULL
AND type = ?
AND transaction_date >= ?
AND transaction_date < ?
''',
      whereArgs: [type.code, startDateInclusive, endDateExclusive],
    );
  }

  Future<int> _sum({
    required String where,
    required List<Object?> whereArgs,
  }) async {
    final rows = await _db.rawQuery('''
SELECT COALESCE(SUM(amount_cents), 0) AS total
FROM ${DatabaseSchema.transactionsTable}
WHERE $where
''', whereArgs);
    final value = rows.first['total'];
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return 0;
  }
}

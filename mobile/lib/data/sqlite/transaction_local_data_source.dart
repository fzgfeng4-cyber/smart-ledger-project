import 'package:sqflite/sqflite.dart';

import '../../domain/budget/budget.dart';
import '../../domain/import/import_batch_record.dart';
import '../../domain/models/ledger_transaction.dart';
import '../../domain/models/transaction_type.dart';
import '../../shared/clock.dart';
import '../statistics/transaction_statistics_data.dart';
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

  Future<List<LedgerTransaction>> insertBatch(
    Iterable<NewLedgerTransaction> transactions, {
    required DateTime now,
  }) async {
    final entries = transactions.toList(growable: false);
    if (entries.isEmpty) {
      throw StateError('批量新增至少需要一笔账目');
    }

    final timestamp = formatUtcIsoSeconds(now);
    return _db.transaction((transaction) async {
      final ids = <int>[];
      for (final entry in entries) {
        final id = await transaction.insert(DatabaseSchema.transactionsTable, {
          'amount_cents': entry.amountCents,
          'type': entry.type.code,
          'category': entry.category,
          'note': entry.note,
          'original_text': entry.originalText,
          'transaction_date': entry.transactionDate,
          'created_at': timestamp,
          'updated_at': timestamp,
          'deleted_at': null,
        }, conflictAlgorithm: ConflictAlgorithm.abort);
        ids.add(id);
      }

      final created = <LedgerTransaction>[];
      for (final id in ids) {
        final rows = await transaction.query(
          DatabaseSchema.transactionsTable,
          where: 'id = ?',
          whereArgs: [id],
          limit: 1,
        );
        if (rows.isEmpty) {
          throw StateError('批量新增后无法读取记录: $id');
        }
        created.add(LedgerTransaction.fromMap(rows.first));
      }
      return created;
    });
  }

  Future<List<LedgerTransaction>> insertImportedBatch({
    required String source,
    required String fingerprint,
    required String fileName,
    required Iterable<NewLedgerTransaction> transactions,
    required DateTime now,
  }) async {
    final entries = transactions.toList(growable: false);
    if (entries.isEmpty) {
      throw StateError('导入批次至少需要一笔账目');
    }

    final timestamp = formatUtcIsoSeconds(now);
    return _db.transaction((transaction) async {
      final batchId = await transaction.insert(
        DatabaseSchema.importBatchesTable,
        {
          'source': source,
          'fingerprint': fingerprint,
          'file_name': fileName,
          'transaction_count': entries.length,
          'imported_at': timestamp,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
      if (batchId == 0) {
        throw const ImportBatchAlreadyExistsException();
      }

      final ids = <int>[];
      for (final entry in entries) {
        final id = await transaction.insert(DatabaseSchema.transactionsTable, {
          'amount_cents': entry.amountCents,
          'type': entry.type.code,
          'category': entry.category,
          'note': entry.note,
          'original_text': entry.originalText,
          'transaction_date': entry.transactionDate,
          'created_at': timestamp,
          'updated_at': timestamp,
          'deleted_at': null,
        }, conflictAlgorithm: ConflictAlgorithm.abort);
        ids.add(id);
      }

      final created = <LedgerTransaction>[];
      for (final id in ids) {
        final rows = await transaction.query(
          DatabaseSchema.transactionsTable,
          where: 'id = ?',
          whereArgs: [id],
          limit: 1,
        );
        if (rows.isEmpty) {
          throw StateError('导入批次新增后无法读取记录: $id');
        }
        created.add(LedgerTransaction.fromMap(rows.first));
      }
      return created;
    });
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

  Future<List<LedgerTransaction>> listActiveInDateRange({
    required String startDateInclusive,
    required String endDateExclusive,
  }) async {
    final rows = await _db.query(
      DatabaseSchema.transactionsTable,
      where:
          '''
deleted_at IS NULL
AND $_validTransactionDateSql
AND transaction_date >= ?
AND transaction_date < ?
''',
      whereArgs: [startDateInclusive, endDateExclusive],
      orderBy: 'transaction_date ASC, id ASC',
    );
    return rows.map(LedgerTransaction.fromMap).toList(growable: false);
  }

  Future<List<LedgerTransaction>> listAllForBackup() async {
    final rows = await _db.query(
      DatabaseSchema.transactionsTable,
      orderBy: 'id ASC',
    );
    return rows.map(LedgerTransaction.fromMap).toList();
  }

  Future<void> replaceAllForBackup(
    Iterable<LedgerTransaction> transactions, {
    Iterable<Budget> budgets = const [],
    Iterable<ImportBatchRecord> importBatches = const [],
  }) async {
    final transactionEntries = transactions.toList(growable: false);
    final budgetEntries = budgets.toList(growable: false);
    final importBatchEntries = importBatches.toList(growable: false);
    await _db.transaction((transaction) async {
      await transaction.delete(DatabaseSchema.importBatchesTable);
      await transaction.delete(DatabaseSchema.budgetsTable);
      await transaction.delete(DatabaseSchema.transactionsTable);
      for (final entry in transactionEntries) {
        await transaction.insert(
          DatabaseSchema.transactionsTable,
          entry.toMap(),
          conflictAlgorithm: ConflictAlgorithm.abort,
        );
      }
      for (final budget in budgetEntries) {
        await transaction.insert(
          DatabaseSchema.budgetsTable,
          budget.toMap(),
          conflictAlgorithm: ConflictAlgorithm.abort,
        );
      }
      for (final importBatch in importBatchEntries) {
        await transaction.insert(
          DatabaseSchema.importBatchesTable,
          importBatch.toMap(),
          conflictAlgorithm: ConflictAlgorithm.abort,
        );
      }
    });
  }

  Future<List<ImportBatchRecord>> listAllImportBatches() async {
    final rows = await _db.query(
      DatabaseSchema.importBatchesTable,
      orderBy: 'imported_at DESC, id DESC',
    );
    return rows.map(ImportBatchRecord.fromMap).toList(growable: false);
  }

  Future<List<LedgerTransaction>> search({
    required int limit,
    required int offset,
    String? categoryCode,
    String? keyword,
    String? startDateInclusive,
    String? endDateExclusive,
  }) async {
    final where = <String>['deleted_at IS NULL'];
    final whereArgs = <Object?>[];

    final normalizedCategory = categoryCode?.trim();
    if (normalizedCategory != null && normalizedCategory.isNotEmpty) {
      where.add('category = ?');
      whereArgs.add(normalizedCategory);
    }

    final normalizedKeyword = keyword?.trim();
    if (normalizedKeyword != null && normalizedKeyword.isNotEmpty) {
      where.add(
        "(instr(COALESCE(note, ''), ?) > 0 OR instr(original_text, ?) > 0)",
      );
      whereArgs.addAll([normalizedKeyword, normalizedKeyword]);
    }

    final normalizedStartDate = startDateInclusive?.trim();
    if (normalizedStartDate != null && normalizedStartDate.isNotEmpty) {
      where.add('transaction_date >= ?');
      whereArgs.add(normalizedStartDate);
    }

    final normalizedEndDate = endDateExclusive?.trim();
    if (normalizedEndDate != null && normalizedEndDate.isNotEmpty) {
      where.add('transaction_date < ?');
      whereArgs.add(normalizedEndDate);
    }

    final rows = await _db.query(
      DatabaseSchema.transactionsTable,
      where: where.join(' AND '),
      whereArgs: whereArgs,
      orderBy: 'transaction_date DESC, updated_at DESC, id DESC',
      limit: limit,
      offset: offset,
    );
    return rows.map(LedgerTransaction.fromMap).toList();
  }

  Future<LedgerTransaction?> findLatestMatchingActive({
    required int amountCents,
    required TransactionType type,
    required String category,
    required String? note,
    required String transactionDate,
  }) async {
    final where = StringBuffer()
      ..write('deleted_at IS NULL')
      ..write('\nAND transaction_date = ?')
      ..write('\nAND amount_cents = ?')
      ..write('\nAND type = ?')
      ..write('\nAND category = ?');
    final whereArgs = <Object?>[
      transactionDate,
      amountCents,
      type.code,
      category,
    ];
    if (note == null) {
      where.write('\nAND note IS NULL');
    } else {
      where.write('\nAND note = ?');
      whereArgs.add(note);
    }

    final rows = await _db.query(
      DatabaseSchema.transactionsTable,
      where: where.toString(),
      whereArgs: whereArgs,
      orderBy: 'transaction_date DESC, updated_at DESC, id DESC',
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return LedgerTransaction.fromMap(rows.first);
  }

  Future<TransactionStatisticsData> queryStatistics({
    required String startDateInclusive,
    required String endDateExclusive,
  }) async {
    return _db.transaction((transaction) async {
      final rows = await transaction.query(
        DatabaseSchema.transactionsTable,
        columns: const ['type', 'category', 'amount_cents'],
        where:
            '''
deleted_at IS NULL
AND $_validTransactionDateSql
AND transaction_date >= ?
AND transaction_date < ?
''',
        whereArgs: [startDateInclusive, endDateExclusive],
        orderBy: 'category ASC',
      );

      var expenseTotal = BigInt.zero;
      var incomeTotal = BigInt.zero;
      final categoryTotals = <String, BigInt>{};
      for (final row in rows) {
        final amount = BigInt.from(_readInteger(row['amount_cents']));
        final type = row['type'];
        final category = row['category'];
        if (type is! String || category is! String) {
          throw StateError('统计记录的 type 或 category 不是字符串');
        }
        if (type == TransactionType.expense.code) {
          expenseTotal += amount;
          categoryTotals.update(
            category,
            (current) => current + amount,
            ifAbsent: () => amount,
          );
        } else if (type == TransactionType.income.code) {
          incomeTotal += amount;
        } else {
          throw StateError('统计记录包含未知收支类型: $type');
        }
      }

      final orderedCategories = categoryTotals.keys.toList()..sort();
      return TransactionStatisticsData(
        expenseTotalCents: _bigIntToInteger(expenseTotal),
        incomeTotalCents: _bigIntToInteger(incomeTotal),
        expenseCategories: orderedCategories.map(
          (category) => TransactionCategoryAmount(
            categoryCode: category,
            amountCents: _bigIntToInteger(categoryTotals[category]!),
          ),
        ),
      );
    });
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
    final rows = await _db.query(
      DatabaseSchema.transactionsTable,
      columns: const ['amount_cents'],
      where: '$where AND $_validTransactionDateSql',
      whereArgs: whereArgs,
    );
    var total = BigInt.zero;
    for (final row in rows) {
      total += BigInt.from(_readInteger(row['amount_cents']));
    }
    return _bigIntToInteger(total);
  }

  static int _readInteger(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is double &&
        value.isFinite &&
        value == value.truncateToDouble() &&
        value > 0 &&
        value <= DatabaseSchema.maxSqliteInteger) {
      return value.toInt();
    }
    throw StateError('SQLite 金额字段不是可安全转换的整数分');
  }

  static int _bigIntToInteger(BigInt value) {
    final max = BigInt.from(DatabaseSchema.maxSqliteInteger);
    if (value < BigInt.zero || value > max) {
      throw StateError('统计金额超出 SQLite 整数范围');
    }
    return value.toInt();
  }
}

const _validTransactionDateSql = '''
length(transaction_date) = 10
AND transaction_date GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]'
AND date(transaction_date) = transaction_date
''';

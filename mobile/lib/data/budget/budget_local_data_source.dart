import 'package:sqflite/sqflite.dart';

import '../../domain/budget/budget.dart';
import '../../shared/clock.dart';
import '../sqlite/database_schema.dart';

final class BudgetLocalDataSource {
  const BudgetLocalDataSource(this._db);

  final Database _db;

  Future<Budget> insert(NewBudget budget, {required DateTime now}) async {
    final id = await _db.insert(DatabaseSchema.budgetsTable, {
      'category_code': budget.categoryCode,
      'month': budget.month,
      'amount_cents': budget.amountCents,
      'enabled': budget.enabled ? 1 : 0,
      'created_at': formatUtcIsoSeconds(now),
      'updated_at': formatUtcIsoSeconds(now),
    }, conflictAlgorithm: ConflictAlgorithm.abort);

    final created = await findById(id);
    if (created == null) {
      throw StateError('新增预算后无法读取记录');
    }
    return created;
  }

  Future<Budget?> findById(int id) async {
    final rows = await _db.query(
      DatabaseSchema.budgetsTable,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return Budget.fromMap(rows.first);
  }

  Future<Budget?> findByCategoryAndMonth({
    required String categoryCode,
    required String month,
    bool includeDisabled = true,
  }) async {
    final where = <String>['category_code = ?', 'month = ?'];
    final whereArgs = <Object?>[categoryCode, month];
    if (!includeDisabled) {
      where.add('enabled = 1');
    }

    final rows = await _db.query(
      DatabaseSchema.budgetsTable,
      where: where.join(' AND '),
      whereArgs: whereArgs,
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return Budget.fromMap(rows.first);
  }

  Future<List<Budget>> listForMonth({
    required String month,
    bool enabledOnly = true,
  }) async {
    final rows = await _db.query(
      DatabaseSchema.budgetsTable,
      where: enabledOnly ? 'month = ? AND enabled = 1' : 'month = ?',
      whereArgs: [month],
      orderBy: 'category_code ASC, id ASC',
    );
    return rows.map(Budget.fromMap).toList(growable: false);
  }

  Future<List<Budget>> listAllForBackup() async {
    final rows = await _db.query(
      DatabaseSchema.budgetsTable,
      orderBy: 'id ASC',
    );
    return rows.map(Budget.fromMap).toList(growable: false);
  }

  Future<Budget?> update(
    int id,
    BudgetUpdate update, {
    required DateTime now,
  }) async {
    final values = <String, Object?>{'updated_at': formatUtcIsoSeconds(now)};
    if (update.categoryCode != null) {
      values['category_code'] = update.categoryCode;
    }
    if (update.month != null) {
      values['month'] = update.month;
    }
    if (update.amountCents != null) {
      values['amount_cents'] = update.amountCents;
    }
    final enabled = update.enabled;
    if (enabled != null) {
      values['enabled'] = enabled ? 1 : 0;
    }

    final count = await _db.update(
      DatabaseSchema.budgetsTable,
      values,
      where: 'id = ?',
      whereArgs: [id],
    );
    if (count == 0) {
      return null;
    }
    return findById(id);
  }

  Future<bool> delete(int id) async {
    final count = await _db.delete(
      DatabaseSchema.budgetsTable,
      where: 'id = ?',
      whereArgs: [id],
    );
    return count > 0;
  }
}

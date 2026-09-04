import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:smartledger/data/budget/budget_local_data_source.dart';
import 'package:smartledger/data/budget/budget_repository.dart';
import 'package:smartledger/data/sqlite/app_database.dart';
import 'package:smartledger/domain/budget/budget.dart';
import 'package:smartledger/domain/budget/budget_validator.dart';
import 'package:smartledger/shared/clock.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  late Directory tempDir;
  late Database db;
  late MutableClock clock;
  late BudgetRepository repository;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp(
      'smart_ledger_budget_test_',
    );
    db = await AppDatabase.openAtPath(
      path.join(tempDir.path, 'smart-ledger.sqlite'),
      databaseFactory: databaseFactoryFfi,
    );
    clock = MutableClock(DateTime.utc(2026, 9, 1, 10, 30));
    repository = BudgetRepository(BudgetLocalDataSource(db), clock: clock);
  });

  tearDown(() async {
    await db.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('创建、查询、更新和删除预算保留时间与启用状态', () async {
    final created = await repository.create(
      const NewBudget(
        categoryCode: 'groceries_food',
        month: ' 2026-09 ',
        amountCents: 35800,
      ),
    );

    expect(created.id, greaterThan(0));
    expect(created.categoryCode, 'groceries_food');
    expect(created.month, '2026-09');
    expect(created.amountCents, 35800);
    expect(created.enabled, isTrue);
    expect(created.createdAt, DateTime.utc(2026, 9, 1, 10, 30));
    expect(created.updatedAt, created.createdAt);

    clock.set(DateTime.utc(2026, 9, 2, 8));
    final updated = await repository.update(
      created.id,
      const BudgetUpdate(amountCents: 42000, enabled: false),
    );

    expect(updated, isNotNull);
    expect(updated!.id, created.id);
    expect(updated.createdAt, created.createdAt);
    expect(updated.updatedAt, DateTime.utc(2026, 9, 2, 8));
    expect(updated.amountCents, 42000);
    expect(updated.enabled, isFalse);
    expect(
      await repository.findByCategoryAndMonth(
        categoryCode: 'groceries_food',
        month: '2026-09',
      ),
      isNotNull,
    );
    expect(await repository.listForMonth('2026-09'), isEmpty);
    expect(
      await repository.listForMonth('2026-09', enabledOnly: false),
      hasLength(1),
    );

    final reenabled = await repository.update(
      created.id,
      const BudgetUpdate(enabled: true),
    );
    expect(reenabled?.enabled, isTrue);
    expect(await repository.listForMonth('2026-09'), hasLength(1));

    expect(await repository.delete(created.id), isTrue);
    expect(await repository.findById(created.id), isNull);
    expect(await repository.delete(created.id), isFalse);
  });

  test('金额、月份、分类和重复预算在写入前被拒绝', () async {
    final invalidInputs = [
      const NewBudget(categoryCode: 'dining', month: '2026-09', amountCents: 0),
      const NewBudget(
        categoryCode: 'salary',
        month: '2026-09',
        amountCents: 100,
      ),
      const NewBudget(
        categoryCode: 'unknown',
        month: '2026-09',
        amountCents: 100,
      ),
      const NewBudget(
        categoryCode: 'dining',
        month: '2026-9',
        amountCents: 100,
      ),
      const NewBudget(
        categoryCode: 'dining',
        month: '2026-13',
        amountCents: 100,
      ),
    ];

    for (final input in invalidInputs) {
      await expectLater(
        repository.create(input),
        throwsA(isA<BudgetValidationException>()),
      );
    }
    expect(await repository.listForMonth('2026-09'), isEmpty);
  });

  test('同分类同月份只能存在一条预算，停用记录也占用唯一键', () async {
    await repository.create(
      const NewBudget(
        categoryCode: 'dining',
        month: '2026-09',
        amountCents: 10000,
        enabled: false,
      ),
    );

    await expectLater(
      repository.create(
        const NewBudget(
          categoryCode: 'dining',
          month: '2026-09',
          amountCents: 20000,
        ),
      ),
      throwsA(isA<BudgetValidationException>()),
    );

    final otherMonth = await repository.create(
      const NewBudget(
        categoryCode: 'dining',
        month: '2026-10',
        amountCents: 20000,
      ),
    );
    expect(otherMonth.month, '2026-10');
  });

  test('更新分类或月份时继续检查唯一性', () async {
    final first = await repository.create(
      const NewBudget(
        categoryCode: 'dining',
        month: '2026-09',
        amountCents: 10000,
      ),
    );
    final second = await repository.create(
      const NewBudget(
        categoryCode: 'transportation',
        month: '2026-09',
        amountCents: 20000,
      ),
    );

    await expectLater(
      repository.update(second.id, const BudgetUpdate(categoryCode: 'dining')),
      throwsA(isA<BudgetValidationException>()),
    );
    final updated = await repository.update(
      first.id,
      const BudgetUpdate(month: '2026-10'),
    );
    expect(updated!.month, '2026-10');
  });
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

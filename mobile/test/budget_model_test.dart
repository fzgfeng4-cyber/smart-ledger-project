import 'package:flutter_test/flutter_test.dart';
import 'package:smartledger/domain/budget/budget.dart';

void main() {
  test('预算模型可以在 SQLite map 与领域对象之间往返', () {
    final budget = Budget(
      id: 3,
      categoryCode: 'dining',
      month: '2026-09',
      amountCents: 120000,
      enabled: true,
      createdAt: DateTime.utc(2026, 9, 1, 1, 2, 3),
      updatedAt: DateTime.utc(2026, 9, 1, 1, 2, 3),
    );

    final restored = Budget.fromMap(budget.toMap());

    expect(restored.id, budget.id);
    expect(restored.categoryCode, budget.categoryCode);
    expect(restored.month, budget.month);
    expect(restored.amountCents, budget.amountCents);
    expect(restored.enabled, isTrue);
    expect(restored.createdAt, budget.createdAt);
    expect(restored.updatedAt, budget.updatedAt);
  });

  test('新预算默认启用，更新对象只携带明确修改字段', () {
    const budget = NewBudget(
      categoryCode: 'dining',
      month: '2026-09',
      amountCents: 120000,
    );
    const update = BudgetUpdate(amountCents: 135000, enabled: false);

    expect(budget.enabled, isTrue);
    expect(update.hasChanges, isTrue);
    expect(update.categoryCode, isNull);
    expect(update.month, isNull);
  });
}

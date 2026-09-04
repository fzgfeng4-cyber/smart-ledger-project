import 'package:flutter_test/flutter_test.dart';
import 'package:smartledger/domain/budget/budget.dart';
import 'package:smartledger/domain/budget/budget_calculation.dart';
import 'package:smartledger/domain/models/ledger_transaction.dart';
import 'package:smartledger/domain/models/transaction_type.dart';
import 'package:smartledger/shared/clock.dart';

void main() {
  test('只统计目标月份的有效支出并按分类汇总', () {
    final targetBudget = _budget(categoryCode: 'dining');
    final otherBudget = _budget(categoryCode: 'groceries_food');
    final deletedExpense = _transaction(
      amountCents: 700,
      category: 'dining',
      deletedAt: DateTime.utc(2026, 9, 5),
    );
    final transactions = [
      _transaction(amountCents: 1250, category: 'dining'),
      _transaction(amountCents: 300, category: 'dining', date: '2026-09-30'),
      _transaction(
        amountCents: 900,
        category: 'dining',
        type: TransactionType.income,
      ),
      deletedExpense,
      _transaction(amountCents: 500, category: 'dining', date: '2026-08-31'),
      _transaction(amountCents: 200, category: 'groceries_food'),
    ];

    final result =
        BudgetCalculationService(
          clock: _FixedClock(DateTime.utc(2026, 9, 10, 8)),
        ).calculate(
          month: '2026-09',
          budgets: [targetBudget, otherBudget],
          transactions: transactions,
        );

    expect(result, hasLength(2));
    expect(result[0].usedCents, 1250);
    expect(result[1].usedCents, 200);
    expect(result[0].budgetAmountCents, 3000);
    expect(result[0].remainingCents, 1750);
    expect(result[0].overspentCents, 0);
    expect(deletedExpense.isDeleted, isTrue);
  });

  test('本月已过天数作为日均分母，预计天数向上取整且至少为一天', () {
    final result =
        BudgetCalculationService(
          clock: _FixedClock(DateTime.utc(2026, 9, 10, 8)),
        ).calculate(
          month: '2026-09',
          budgets: [_budget(amountCents: 1000)],
          transactions: [_transaction(amountCents: 300)],
        );

    // 日均 30 分，剩余 700 分，700 / 30 向上取整为 24 天。
    expect(result.single.estimatedDaysToExhaustion, 24);

    final minimumResult =
        BudgetCalculationService(
          clock: _FixedClock(DateTime.utc(2026, 9, 10, 8)),
        ).calculate(
          month: '2026-09',
          budgets: [_budget(amountCents: 1000)],
          transactions: [_transaction(amountCents: 999)],
        );
    expect(minimumResult.single.estimatedDaysToExhaustion, 1);
  });

  test('没有消费时不预计，状态仍为预算内', () {
    final result = BudgetCalculationService(
      clock: _FixedClock(DateTime.utc(2026, 9, 1, 8)),
    ).calculate(month: '2026-09', budgets: [_budget()], transactions: const []);

    expect(result.single.usedCents, 0);
    expect(result.single.status, BudgetStatus.withinBudget);
    expect(result.single.estimatedDaysToExhaustion, isNull);
  });

  test('预算为零不除零，已消费时单独计算超支金额', () {
    final result =
        BudgetCalculationService(
          clock: _FixedClock(DateTime.utc(2026, 9, 5, 8)),
        ).calculate(
          month: '2026-09',
          budgets: [_budget(amountCents: 0)],
          transactions: [_transaction(amountCents: 250)],
        );

    expect(result.single.remainingCents, 0);
    expect(result.single.overspentCents, 250);
    expect(result.single.status, BudgetStatus.overspent);
    expect(result.single.estimatedDaysToExhaustion, isNull);
  });

  test('刚好用尽与超支分别标记，剩余金额不为负数', () {
    final exact =
        BudgetCalculationService(
              clock: _FixedClock(DateTime.utc(2026, 9, 5, 8)),
            )
            .calculate(
              month: '2026-09',
              budgets: [_budget(amountCents: 1000)],
              transactions: [_transaction(amountCents: 1000)],
            )
            .single;
    expect(exact.status, BudgetStatus.usedUp);
    expect(exact.remainingCents, 0);
    expect(exact.overspentCents, 0);
    expect(exact.estimatedDaysToExhaustion, isNull);

    final over =
        BudgetCalculationService(
              clock: _FixedClock(DateTime.utc(2026, 9, 5, 8)),
            )
            .calculate(
              month: '2026-09',
              budgets: [_budget(amountCents: 1000)],
              transactions: [_transaction(amountCents: 1250)],
            )
            .single;
    expect(over.status, BudgetStatus.overspent);
    expect(over.remainingCents, 0);
    expect(over.overspentCents, 250);
  });

  test('只返回指定月份预算，预测不会写入交易', () {
    final transaction = _transaction(amountCents: 300);
    final result =
        BudgetCalculationService(
          clock: _FixedClock(DateTime.utc(2026, 9, 10, 8)),
        ).calculate(
          month: '2026-09',
          budgets: [
            _budget(month: '2026-09'),
            _budget(categoryCode: 'dining', month: '2026-10'),
          ],
          transactions: [transaction],
        );

    expect(result, hasLength(1));
    expect(transaction.amountCents, 300);
    expect(transaction.deletedAt, isNull);
    expect(transaction.transactionDate, '2026-09-01');
  });

  test('停用预算不会进入使用情况计算', () {
    final disabled = _budget().copyWith(enabled: false);
    final result =
        BudgetCalculationService(
          clock: _FixedClock(DateTime.utc(2026, 9, 10, 8)),
        ).calculate(
          month: '2026-09',
          budgets: [disabled],
          transactions: [_transaction(amountCents: 500)],
        );

    expect(result, isEmpty);
  });

  test('非法和未来日期不会计入当月预算使用', () {
    final result =
        BudgetCalculationService(
          clock: _FixedClock(DateTime.utc(2026, 9, 10, 8)),
        ).calculate(
          month: '2026-09',
          budgets: [_budget()],
          transactions: [
            _transaction(amountCents: 300, date: '2026-09-10'),
            _transaction(amountCents: 400, date: '2026-09-11'),
            _transaction(amountCents: 500, date: '2026-09-99'),
          ],
        );

    expect(result.single.usedCents, 300);
  });
}

Budget _budget({
  String categoryCode = 'dining',
  String month = '2026-09',
  int amountCents = 3000,
}) {
  return Budget(
    id: categoryCode == 'dining' ? 1 : 2,
    categoryCode: categoryCode,
    month: month,
    amountCents: amountCents,
    enabled: true,
    createdAt: DateTime.utc(2026, 9, 1),
    updatedAt: DateTime.utc(2026, 9, 1),
  );
}

LedgerTransaction _transaction({
  int amountCents = 300,
  TransactionType type = TransactionType.expense,
  String category = 'dining',
  String date = '2026-09-01',
  DateTime? deletedAt,
}) {
  return LedgerTransaction(
    id: amountCents,
    amountCents: amountCents,
    type: type,
    category: category,
    note: '测试',
    originalText: '测试账目',
    transactionDate: date,
    createdAt: DateTime.utc(2026, 9, 1),
    updatedAt: DateTime.utc(2026, 9, 1),
    deletedAt: deletedAt,
  );
}

final class _FixedClock implements Clock {
  const _FixedClock(this._now);

  final DateTime _now;

  @override
  DateTime now() => _now;
}

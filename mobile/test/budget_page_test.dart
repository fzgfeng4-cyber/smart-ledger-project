import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartledger/domain/budget/budget.dart';
import 'package:smartledger/domain/budget/budget_calculation.dart';
import 'package:smartledger/ui/budget/budget_page.dart';

void main() {
  testWidgets('空态展示月份标题和新增预算按钮', (tester) async {
    await tester.pumpWidget(
      _testApp(
        calculations: const [],
        onCreate: (_) {},
        onEdit: (_, _) {},
        onDisable: (_) {},
      ),
    );

    expect(find.text('2026-09'), findsOneWidget);
    expect(find.byKey(const Key('budget-empty-state')), findsOneWidget);
    expect(find.byKey(const Key('add-budget-button')), findsOneWidget);
  });

  testWidgets('新增预算将元输入转换为整数分并回调 NewBudget', (tester) async {
    NewBudget? createdBudget;

    await tester.pumpWidget(
      _testApp(
        calculations: const [],
        onCreate: (budget) => createdBudget = budget,
        onEdit: (_, _) {},
        onDisable: (_) {},
      ),
    );

    await tester.tap(find.byKey(const Key('add-budget-button')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('budget-amount-field')),
      '12.34',
    );
    await tester.tap(find.byKey(const Key('budget-category-field')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('餐饮').last);
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('budget-form-submit')));
    await tester.pumpAndSettle();

    expect(createdBudget?.categoryCode, 'dining');
    expect(createdBudget?.month, '2026-09');
    expect(createdBudget?.amountCents, 1234);
    expect(createdBudget?.enabled, isTrue);
  });

  testWidgets('超支同时展示红色状态和明确文字图标', (tester) async {
    final calculation = _calculation(
      amountCents: 3000,
      usedCents: 3500,
      remainingCents: 0,
      overspentCents: 500,
      status: BudgetStatus.overspent,
    );

    await tester.pumpWidget(
      _testApp(
        calculations: [calculation],
        onCreate: (_) {},
        onEdit: (_, _) {},
        onDisable: (_) {},
      ),
    );

    expect(find.text('已超支'), findsOneWidget);
    expect(find.text('超支 ¥5.00'), findsOneWidget);
    expect(find.byKey(const Key('budget-status-icon-1')), findsOneWidget);

    final status = tester.widget<Text>(
      find.byKey(const Key('budget-status-1')),
    );
    expect(
      status.style?.color,
      ThemeData(useMaterial3: true).colorScheme.error,
    );
  });

  testWidgets('编辑预算回调原始 Budget 和金额变化的 BudgetUpdate', (tester) async {
    final calculation = _calculation(amountCents: 2000);
    Budget? editedBudget;
    BudgetUpdate? update;

    await tester.pumpWidget(
      _testApp(
        calculations: [calculation],
        onCreate: (_) {},
        onEdit: (budget, changed) {
          editedBudget = budget;
          update = changed;
        },
        onDisable: (_) {},
      ),
    );

    await tester.tap(find.byKey(const Key('budget-edit-1')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('budget-amount-field')),
      '25.00',
    );
    await tester.tap(find.byKey(const Key('budget-form-submit')));
    await tester.pumpAndSettle();

    expect(editedBudget, same(calculation.budget));
    expect(update?.amountCents, 2500);
    expect(update?.categoryCode, isNull);
    expect(update?.month, isNull);
    expect(update?.enabled, isNull);
  });

  testWidgets('停用状态和预计用完天数均有明确文案', (tester) async {
    final calculation = _calculation(
      estimatedDaysToExhaustion: 7,
      enabled: false,
    );

    await tester.pumpWidget(
      _testApp(
        calculations: [calculation],
        onCreate: (_) {},
        onEdit: (_, _) {},
        onDisable: (_) {},
      ),
    );

    expect(find.text('已停用'), findsOneWidget);
    expect(find.text('预计用完：7 天'), findsOneWidget);
    expect(find.byKey(const Key('budget-disable-1')), findsNothing);
  });

  testWidgets('停用按钮回调原始 Budget', (tester) async {
    final calculation = _calculation();
    Budget? disabledBudget;

    await tester.pumpWidget(
      _testApp(
        calculations: [calculation],
        onCreate: (_) {},
        onEdit: (_, _) {},
        onDisable: (budget) => disabledBudget = budget,
      ),
    );

    await tester.tap(find.byKey(const Key('budget-disable-1')));
    await tester.pump();

    expect(disabledBudget, same(calculation.budget));
  });

  testWidgets('非法金额不会触发新增回调且错误可见', (tester) async {
    var createCalls = 0;

    await tester.pumpWidget(
      _testApp(
        calculations: const [],
        onCreate: (_) => createCalls += 1,
        onEdit: (_, _) {},
        onDisable: (_) {},
      ),
    );

    await tester.tap(find.byKey(const Key('add-budget-button')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('budget-amount-field')), '0');
    await tester.tap(find.byKey(const Key('budget-form-submit')));
    await tester.pump();

    expect(createCalls, 0);
    expect(find.text('请输入大于 0 的有效金额（元）'), findsOneWidget);
  });
  testWidgets('保存期间禁止重复提交并显示成功反馈', (tester) async {
    final completion = Completer<bool>();
    var createCalls = 0;

    await tester.pumpWidget(
      _testApp(
        calculations: const [],
        onCreate: (_) {},
        onEdit: (_, _) {},
        onDisable: (_) {},
        onCreateAsync: (_) {
          createCalls += 1;
          return completion.future;
        },
      ),
    );

    await tester.tap(find.byKey(const Key('add-budget-button')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('budget-amount-field')),
      '12.34',
    );
    await tester.tap(find.byKey(const Key('budget-category-field')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('餐饮').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('budget-form-submit')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('budget-form-submit')));
    await tester.pump();

    expect(createCalls, 1);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('add-budget-button')))
          .onPressed,
      isNull,
    );

    completion.complete(true);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('budget-feedback-banner')), findsOneWidget);
    expect(find.text('预算已保存。'), findsOneWidget);
  });

  testWidgets('已有预算保存失败时显示错误反馈', (tester) async {
    await tester.pumpWidget(
      _testApp(
        calculations: [_calculation()],
        onCreate: (_) {},
        onEdit: (_, _) {},
        onDisable: (_) {},
        onDisableAsync: (_) async => false,
      ),
    );

    await tester.tap(find.byKey(const Key('budget-disable-1')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('budget-error-banner')), findsOneWidget);
    expect(find.text('预算停用失败，请重试。'), findsOneWidget);
  });

  testWidgets('管理页面显示停用预算并支持重新启用', (tester) async {
    final disabledBudget = _calculation(enabled: false).budget;
    var enableCalls = 0;

    await tester.pumpWidget(
      _testApp(
        calculations: const [],
        managedBudgets: [disabledBudget],
        onCreate: (_) {},
        onEdit: (_, _) {},
        onDisable: (_) {},
        onEnableAsync: (_) async {
          enableCalls += 1;
          return true;
        },
      ),
    );

    expect(find.byKey(const Key('disabled-budgets-section')), findsOneWidget);
    expect(find.byKey(const Key('budget-enable-1')), findsOneWidget);

    await tester.tap(find.byKey(const Key('budget-enable-1')));
    await tester.pumpAndSettle();

    expect(enableCalls, 1);
    expect(find.text('预算已重新启用。'), findsOneWidget);
  });
}

Widget _testApp({
  required List<BudgetCalculation> calculations,
  required BudgetCreateCallback onCreate,
  required BudgetEditCallback onEdit,
  required BudgetDisableCallback onDisable,
  BudgetEnableCallback? onEnable,
  BudgetCreateAsyncCallback? onCreateAsync,
  BudgetEditAsyncCallback? onEditAsync,
  BudgetDisableAsyncCallback? onDisableAsync,
  BudgetEnableAsyncCallback? onEnableAsync,
  List<Budget> managedBudgets = const [],
  bool isBusy = false,
  String? feedbackMessage,
  String? errorMessage,
}) {
  return MaterialApp(
    theme: ThemeData(useMaterial3: true),
    home: BudgetPage(
      month: '2026-09',
      calculations: calculations,
      onCreate: onCreate,
      onEdit: onEdit,
      onDisable: onDisable,
      onEnable: onEnable,
      onCreateAsync: onCreateAsync,
      onEditAsync: onEditAsync,
      onDisableAsync: onDisableAsync,
      onEnableAsync: onEnableAsync,
      managedBudgets: managedBudgets,
      isBusy: isBusy,
      feedbackMessage: feedbackMessage,
      errorMessage: errorMessage,
    ),
  );
}

BudgetCalculation _calculation({
  int amountCents = 3000,
  int usedCents = 1000,
  int remainingCents = 2000,
  int overspentCents = 0,
  BudgetStatus status = BudgetStatus.withinBudget,
  int? estimatedDaysToExhaustion,
  bool enabled = true,
}) {
  final budget = Budget(
    id: 1,
    categoryCode: 'dining',
    month: '2026-09',
    amountCents: amountCents,
    enabled: enabled,
    createdAt: DateTime.utc(2026, 9, 1),
    updatedAt: DateTime.utc(2026, 9, 1),
  );
  return BudgetCalculation(
    budget: budget,
    budgetAmountCents: amountCents,
    usedCents: usedCents,
    remainingCents: remainingCents,
    overspentCents: overspentCents,
    status: status,
    estimatedDaysToExhaustion: estimatedDaysToExhaustion,
  );
}

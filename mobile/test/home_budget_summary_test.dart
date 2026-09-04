import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartledger/app/smart_ledger_app.dart';
import 'package:smartledger/domain/budget/budget.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  late TestLedgerFixture fixture;

  setUp(() async {
    fixture = await TestLedgerFixture.create(now: DateTime(2026, 9, 10, 8));
  });

  tearDown(() async {
    await fixture.dispose();
  });

  testWidgets('首页显示预算已使用、剩余和预计耗尽天数，并可进入预算页', (tester) async {
    await tester.runAsync(() async {
      await fixture.budgetRepository.create(
        const NewBudget(
          categoryCode: 'dining',
          month: '2026-09',
          amountCents: 3000,
        ),
      );
      await fixture.seed(
        amountCents: 1000,
        category: 'dining',
        transactionDate: '2026-09-01',
      );
      await fixture.controller.initialize();
    });
    await _pumpApp(tester, fixture);

    expect(find.byKey(const Key('home-budget-summary')), findsOneWidget);
    expect(find.text('已使用'), findsOneWidget);
    expect(find.text('剩余'), findsOneWidget);
    final budgetSummary = find.byKey(const Key('home-budget-summary'));
    expect(
      find.descendant(of: budgetSummary, matching: find.text('¥10.00')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: budgetSummary, matching: find.text('¥20.00')),
      findsOneWidget,
    );
    expect(find.text('预计耗尽：20 天'), findsOneWidget);

    await tester.ensureVisible(find.byKey(const Key('home-budget-entry')));
    await tester.tap(find.byKey(const Key('home-budget-entry')));
    await tester.pump();
    await tester.runAsync(() async {
      for (var attempt = 0; attempt < 80; attempt += 1) {
        if (!fixture.controller.isBudgetBusy) {
          return;
        }
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      fail('预算页初始化未在真实异步等待窗口内完成');
    });
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const Key('budget-page')), findsOneWidget);
  });

  testWidgets('首页对超支预算显示红色提醒', (tester) async {
    await tester.runAsync(() async {
      await fixture.budgetRepository.create(
        const NewBudget(
          categoryCode: 'dining',
          month: '2026-09',
          amountCents: 3000,
        ),
      );
      await fixture.seed(
        amountCents: 3500,
        category: 'dining',
        transactionDate: '2026-09-01',
      );
      await fixture.controller.initialize();
    });
    await _pumpApp(tester, fixture);

    expect(find.text('已超支 ¥5.00'), findsOneWidget);
    final warning = tester.widget<Text>(find.text('已超支 ¥5.00'));
    expect(
      warning.style?.color,
      ColorScheme.fromSeed(
        seedColor: const Color(0xFF0F7B6C),
        brightness: Brightness.light,
      ).error,
    );
  });

  testWidgets('首页处理无预算和有预算但无消费的空数据', (tester) async {
    await tester.runAsync(() => fixture.controller.initialize());
    await _pumpApp(tester, fixture);

    expect(find.byKey(const Key('home-budget-empty-state')), findsOneWidget);
    expect(find.byKey(const Key('quick-input')), findsOneWidget);
    expect(find.byKey(const Key('search-input')), findsOneWidget);

    await tester.runAsync(() async {
      await fixture.budgetRepository.create(
        const NewBudget(
          categoryCode: 'dining',
          month: '2026-09',
          amountCents: 3000,
        ),
      );
      await fixture.controller.refreshBudgets();
    });
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('home-budget-summary')), findsOneWidget);
    expect(find.text('暂无消费，暂不预测耗尽时间'), findsOneWidget);
  });

  testWidgets('首页预算加载失败显示错误并支持重试', (tester) async {
    await tester.runAsync(() async {
      await fixture.budgetRepository.create(
        const NewBudget(
          categoryCode: 'dining',
          month: '2026-09',
          amountCents: 3000,
        ),
      );
      await fixture.controller.initialize();
      fixture.controller.failNextBudgetRefreshForTest();
      await fixture.controller.refreshBudgets();
    });
    await _pumpApp(tester, fixture);

    expect(find.byKey(const Key('home-budget-error-state')), findsOneWidget);
    expect(find.text('预算加载失败，请重试。'), findsOneWidget);

    await tester.ensureVisible(find.byKey(const Key('home-budget-retry')));
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('home-budget-retry')));
      await _waitForBudgetIdle(fixture);
    });
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('home-budget-summary')), findsOneWidget);
  });

  testWidgets('首页预算加载中显示稳定加载态', (tester) async {
    await tester.pumpWidget(SmartLedgerApp(controller: fixture.controller));
    final refresh = fixture.controller.refreshBudgets();
    await tester.pump();

    expect(find.byKey(const Key('home-budget-loading')), findsOneWidget);
    await tester.runAsync(() => refresh);
    await tester.pump();
    expect(find.byKey(const Key('home-budget-loading')), findsNothing);
  });
}

Future<void> _pumpApp(WidgetTester tester, TestLedgerFixture fixture) async {
  await tester.pumpWidget(SmartLedgerApp(controller: fixture.controller));
  await tester.pumpAndSettle();
}

Future<void> _waitForBudgetIdle(TestLedgerFixture fixture) async {
  for (var attempt = 0; attempt < 80; attempt += 1) {
    if (!fixture.controller.isBudgetBusy) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  fail('预算控制器在真实异步等待窗口内未完成加载');
}

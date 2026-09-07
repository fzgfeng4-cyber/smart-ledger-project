import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartledger/app/smart_ledger_app.dart';
import 'package:smartledger/domain/models/transaction_type.dart';

import 'test_support.dart';

void main() {
  late TestLedgerFixture fixture;

  setUpAll(() async {
    fixture = await TestLedgerFixture.create();
  });

  tearDownAll(() async {
    await fixture.dispose();
  });

  setUp(() async {
    await fixture.reset();
  });

  testWidgets('统计页展示本月分类占比并排除软删除', (tester) async {
    await tester.runAsync(() async {
      await fixture.seed(
        amountCents: 7000,
        category: 'dining',
        originalText: '餐饮70元',
      );
      final deleted = await fixture.seed(
        amountCents: 3000,
        category: 'vehicle_fuel',
        originalText: '加油30元',
      );
      await fixture.repository.softDelete(deleted.id);
      await fixture.seed(
        amountCents: 5000,
        type: TransactionType.income,
        category: 'salary',
        originalText: '工资50元',
      );
      await fixture.controller.refresh();
    });

    await tester.pumpWidget(SmartLedgerApp(controller: fixture.controller));
    await tester.pump();
    await tester.tap(find.byIcon(Icons.bar_chart_outlined));
    await tester.pump();
    await _waitForStatisticsIdle(tester, fixture);
    await tester.pump();

    expect(find.byKey(const Key('statistics-page')), findsOneWidget);
    expect(find.text('分类占比'), findsOneWidget);
    expect(find.byKey(const Key('statistics-category-dining')), findsOneWidget);
    expect(
      find.byKey(const Key('statistics-category-vehicle_fuel')),
      findsNothing,
    );
    expect(find.text('¥70.00'), findsAtLeastNWidgets(1));
    expect(find.text('100.0%'), findsAtLeastNWidgets(1));
  });

  testWidgets('统计页可切换月度年度趋势并展示支出分类饼图', (tester) async {
    await tester.runAsync(() async {
      await fixture.seed(
        amountCents: 7000,
        category: 'dining',
        transactionDate: '2026-08-01',
        originalText: '餐饮70元',
      );
      await fixture.seed(
        amountCents: 3000,
        category: 'groceries_food',
        transactionDate: '2026-08-31',
        originalText: '买菜30元',
      );
      await fixture.seed(
        amountCents: 5000,
        type: TransactionType.income,
        category: 'salary',
        transactionDate: '2026-08-15',
        originalText: '工资50元',
      );
    });

    await _openStatisticsPage(tester, fixture);

    expect(find.text('本月趋势'), findsOneWidget);
    expect(find.text('本月（2026年8月）'), findsOneWidget);
    expect(find.text('支出分类'), findsOneWidget);
    expect(find.byKey(const Key('statistics-monthly-chart')), findsOneWidget);
    expect(find.byKey(const Key('statistics-annual-chart')), findsNothing);
    expect(
      find.byKey(const Key('statistics-expense-pie-chart')),
      findsOneWidget,
    );
    expect(find.byType(CustomPaint), findsAtLeastNWidgets(2));
    expect(find.text('工资'), findsNothing);

    await tester.tap(find.byKey(const Key('statistics-yearly-toggle')));
    await tester.pumpAndSettle();

    expect(find.text('年度趋势'), findsOneWidget);
    expect(find.text('本年（2026年）'), findsOneWidget);
    expect(find.byKey(const Key('statistics-monthly-chart')), findsNothing);
    expect(find.byKey(const Key('statistics-annual-chart')), findsOneWidget);
    expect(find.text('2026年支出'), findsOneWidget);
  });

  testWidgets('2026-09-06归入九月而不是六月', (tester) async {
    addTearDown(() => fixture.clock.set(DateTime(2026, 8, 31, 10, 30)));
    fixture.clock.set(DateTime(2026, 9, 6, 10));
    await tester.runAsync(() async {
      await fixture.seed(
        amountCents: 1200,
        category: 'dining',
        transactionDate: '2026-09-06',
        originalText: '早餐12元',
      );
    });

    await _openStatisticsPage(tester, fixture);

    expect(find.text('本月（2026年9月）'), findsOneWidget);
    expect(find.text('9月6日'), findsOneWidget);
    expect(find.text('2026年9月支出'), findsOneWidget);

    await tester.tap(find.byKey(const Key('statistics-yearly-toggle')));
    await tester.pumpAndSettle();

    expect(find.text('本年（2026年）'), findsOneWidget);
    expect(find.text('9月'), findsOneWidget);
    expect(find.text('2026年支出'), findsOneWidget);
  });

  testWidgets('空账本统计页展示空状态', (tester) async {
    await tester.pumpWidget(SmartLedgerApp(controller: fixture.controller));
    await tester.pump();
    await tester.tap(find.byIcon(Icons.bar_chart_outlined));
    await tester.pump();
    await _waitForStatisticsIdle(tester, fixture);
    await tester.pump();

    expect(find.byKey(const Key('statistics-page')), findsOneWidget);
    expect(find.byKey(const Key('statistics-empty-state')), findsOneWidget);
    expect(
      find.byKey(const Key('statistics-monthly-chart-empty')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('statistics-expense-pie-empty')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('statistics-yearly-toggle')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('statistics-annual-chart-empty')),
      findsOneWidget,
    );
  });

  testWidgets('统计加载失败显示错误和重试，重试后恢复图表', (tester) async {
    await _openStatisticsPage(tester, fixture);

    fixture.controller.failNextStatisticsRefreshForTest();
    final failedRefresh = fixture.controller.refreshStatistics();
    await tester.runAsync(() => failedRefresh);
    await tester.pump();

    expect(find.byKey(const Key('statistics-error-state')), findsOneWidget);
    expect(find.byKey(const Key('statistics-retry')), findsOneWidget);

    await tester.tap(find.byKey(const Key('statistics-retry')));
    await _waitForStatisticsIdle(tester, fixture);
    await tester.pump();

    expect(find.byKey(const Key('statistics-error-state')), findsNothing);
    expect(find.byKey(const Key('statistics-monthly-chart')), findsOneWidget);
    expect(find.byKey(const Key('statistics-annual-chart')), findsNothing);

    await tester.tap(find.byKey(const Key('statistics-yearly-toggle')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('statistics-annual-chart')), findsOneWidget);
  });

  testWidgets('图表和分类明细提供可读语义', (tester) async {
    await tester.runAsync(() async {
      await fixture.seed(
        amountCents: 7000,
        category: 'dining',
        transactionDate: '2026-08-01',
        originalText: '餐饮70元',
      );
      await fixture.seed(
        amountCents: 5000,
        type: TransactionType.income,
        category: 'salary',
        transactionDate: '2026-08-15',
        originalText: '工资50元',
      );
    });

    final semantics = tester.ensureSemantics();
    try {
      await _openStatisticsPage(tester, fixture);

      expect(
        find.bySemanticsLabel(RegExp(r'本月趋势.*支出.*¥70\.00')),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(RegExp(r'支出分类.*2026-08-01.*2026-09-01.*¥70\.00')),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(RegExp(r'餐饮.*¥70\.00.*100\.0%')),
        findsOneWidget,
      );
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('统计页窄屏滚动不出现溢出异常', (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(320, 640));
    await tester.runAsync(() async {
      await fixture.seed(
        amountCents: 7000,
        category: 'dining',
        transactionDate: '2026-08-01',
        originalText: '餐饮70元',
      );
      await fixture.seed(
        amountCents: 5000,
        type: TransactionType.income,
        category: 'salary',
        transactionDate: '2026-08-15',
        originalText: '工资50元',
      );
    });

    await _openStatisticsPage(tester, fixture);
    expect(tester.takeException(), isNull);

    await tester.drag(
      find.byKey(const Key('statistics-page')),
      const Offset(0, -480),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('统计页加载时使用不确定进度且不显示虚假百分比', (tester) async {
    await tester.pumpWidget(SmartLedgerApp(controller: fixture.controller));
    await tester.pump();
    await tester.tap(find.byIcon(Icons.bar_chart_outlined));
    final refresh = fixture.controller.refreshStatistics();
    await tester.pump();

    final loading = find.byKey(const Key('statistics-loading'));
    expect(loading, findsOneWidget);
    final indicator = tester.widget<CircularProgressIndicator>(
      find.descendant(
        of: loading,
        matching: find.byType(CircularProgressIndicator),
      ),
    );
    expect(indicator.value, isNull);
    expect(find.text('70%'), findsNothing);

    await tester.runAsync(() => refresh);
    await _waitForStatisticsIdle(tester, fixture);
    await tester.pump();
  });
}

Future<void> _openStatisticsPage(
  WidgetTester tester,
  TestLedgerFixture fixture,
) async {
  await tester.pumpWidget(SmartLedgerApp(controller: fixture.controller));
  await tester.pump();
  await tester.tap(find.byIcon(Icons.bar_chart_outlined));
  await tester.pump();
  await _waitForStatisticsIdle(tester, fixture);
  await tester.pump();
}

Future<void> _waitForStatisticsIdle(
  WidgetTester tester,
  TestLedgerFixture fixture,
) async {
  await tester.runAsync(() async {
    for (var attempt = 0; attempt < 80; attempt += 1) {
      if (!fixture.controller.isStatisticsBusy &&
          !fixture.controller.isStatisticsRefreshPending) {
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    fail('统计页初始化未在真实异步等待窗口内完成');
  });
}

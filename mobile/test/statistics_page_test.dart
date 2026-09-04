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
    expect(find.text('100.0%'), findsOneWidget);
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
    await tester.pump();
  });
}

Future<void> _waitForStatisticsIdle(
  WidgetTester tester,
  TestLedgerFixture fixture,
) async {
  await tester.runAsync(() async {
    for (var attempt = 0; attempt < 80; attempt += 1) {
      if (!fixture.controller.isStatisticsBusy) {
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    fail('统计页初始化未在真实异步等待窗口内完成');
  });
}

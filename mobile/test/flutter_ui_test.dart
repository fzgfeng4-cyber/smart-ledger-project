import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartledger/app/smart_ledger_app.dart';
import 'package:smartledger/domain/models/transaction_type.dart';
import 'package:smartledger/ui/ledger_ui_controller.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'test_support.dart';

void main() {
  sqfliteFfiInit();

  late TestLedgerFixture fixture;

  setUpAll(() async {
    fixture = await TestLedgerFixture.create();
  });

  tearDownAll(() async {
    await fixture.dispose();
  });

  group('空账本 UI', () {
    setUp(() async {
      await fixture.reset();
    });

    testWidgets('首页使用真实数据库渲染空状态和统计', (tester) async {
      await _pumpApp(tester, fixture);

      expect(find.byKey(const Key('home-page')), findsOneWidget);
      expect(find.text('Smart Ledger'), findsOneWidget);
      expect(find.text('今天支出'), findsOneWidget);
      expect(find.text('本月支出'), findsOneWidget);
      expect(find.text('本月收入'), findsOneWidget);
      expect(find.byKey(const Key('quick-input')), findsOneWidget);
      expect(find.byKey(const Key('home-empty-state')), findsOneWidget);
      expect(fixture.controller.recentEntries, isEmpty);
    });

    testWidgets('一句话记账经 Parser 写入真实 SQLite 并刷新统计', (tester) async {
      await _pumpApp(tester, fixture);

      await _tapVisible(tester, find.byKey(const Key('quick-submit')));
      await tester.pumpAndSettle();
      expect(find.text('请输入一笔账，例如：35块买菜。'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('quick-input')), '35块买菜');
      await _tapVisible(tester, find.byKey(const Key('quick-submit')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('editor-page')), findsOneWidget);
      expect(find.text('35块买菜'), findsOneWidget);
      expect(find.text('买菜/食品'), findsOneWidget);
      expect(find.byKey(const Key('original-text-readonly')), findsOneWidget);

      await tester.runAsync(() async {
        await tester.tap(find.byKey(const Key('editor-save')));
        await _waitForControllerIdleInRealAsync(fixture.controller);
      });
      await tester.pumpAndSettle();

      final saved = fixture.controller.visibleEntries.single;
      expect(saved.amountCents, 3500);
      expect(saved.type, TransactionType.expense);
      expect(saved.category, 'groceries_food');
      expect(saved.originalText, '35块买菜');
      expect(fixture.controller.todayExpenseCents, 3500);
      expect(fixture.controller.monthExpenseCents, 3500);
      expect(fixture.controller.monthIncomeCents, 0);
      expect(find.text('¥35.00'), findsAtLeastNWidgets(1));
    });

    testWidgets('AI 确认本地分类后进入编辑页不再重复确认，刷新失败也不误判取消', (tester) async {
      await _pumpApp(tester, fixture);

      await tester.tap(find.byKey(const Key('open-ai-classification')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('ai-classification-input')),
        '蜜雪冰城 12',
      );
      await tester.pump();

      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('ai-confirm-button')))
            .onPressed,
        isNull,
      );
      await tester.drag(
        find.byKey(const Key('ai-classification-scroll')),
        const Offset(0, -300),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('ai-confirm-suggestion')));
      await tester.pump();
      await tester.ensureVisible(find.byKey(const Key('ai-confirm-button')));
      await tester.tap(find.byKey(const Key('ai-confirm-button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('editor-page')), findsOneWidget);
      expect(find.byKey(const Key('issue-panel')), findsNothing);
      expect(_saveButton(tester).onPressed, isNotNull);

      fixture.controller.failNextRefreshForTest();
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const Key('editor-save')));
        for (
          var attempt = 0;
          attempt < 80 && fixture.controller.isBusy;
          attempt += 1
        ) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('ai-classification-page')), findsOneWidget);
      expect(find.text('账目已保存。'), findsOneWidget);
      expect(find.text('已取消确认，账本未修改。'), findsNothing);
      await tester.runAsync(() async {
        expect(await fixture.repository.list(), hasLength(1));
      });
    });

    testWidgets('解析确认页可修改字段并通过 Repository 保存', (tester) async {
      await _pumpApp(tester, fixture);

      await _openDraft(tester, '35块买菜');
      await tester.enterText(
        find.byKey(const Key('editor-amount-field')),
        '36.50',
      );
      await tester.tap(find.byKey(const Key('type-income')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('category-salary')));
      await tester.tap(find.byKey(const Key('category-salary')));
      await tester.ensureVisible(find.byKey(const Key('editor-note-field')));
      await tester.enterText(
        find.byKey(const Key('editor-note-field')),
        '工资修正',
      );
      await tester.ensureVisible(find.byKey(const Key('editor-date-field')));
      await tester.enterText(
        find.byKey(const Key('editor-date-field')),
        '2026-08-31',
      );
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('editor-save')))
            .onPressed,
        isNotNull,
      );

      await _tapAndWaitForControllerIdle(
        tester,
        find.byKey(const Key('editor-save')),
        fixture.controller,
      );

      final saved = fixture.controller.visibleEntries.single;
      expect(saved.amountCents, 3650);
      expect(saved.type, TransactionType.income);
      expect(saved.category, 'salary');
      expect(saved.note, '工资修正');
      expect(saved.originalText, '35块买菜');
      expect(fixture.controller.todayExpenseCents, 0);
      expect(fixture.controller.monthIncomeCents, 3650);
    });

    testWidgets('只有金额时明确待确认，不能默认收支和分类', (tester) async {
      await _pumpApp(tester, fixture);
      await _openDraft(tester, '35');

      expect(find.byKey(const Key('issue-panel')), findsOneWidget);
      expect(find.text('未写元/块，请核对金额。'), findsOneWidget);
      expect(find.text('请选择收入或支出。'), findsOneWidget);
      expect(_saveButton(tester).onPressed, isNull);

      await tester.tap(find.byKey(const Key('type-expense')));
      await tester.pumpAndSettle();
      await _scrollEditorFieldIntoView(tester, const Key('category-dining'));
      await tester.tap(find.byKey(const Key('category-dining')));
      await tester.pumpAndSettle();
      expect(_saveButton(tester).onPressed, isNull);

      await _scrollEditorFieldIntoView(
        tester,
        const Key('acknowledge-amount'),
        delta: 500,
      );
      await tester.tap(find.byKey(const Key('acknowledge-amount')));
      await tester.pumpAndSettle();
      expect(_saveButton(tester).onPressed, isNotNull);
    });

    testWidgets('未来日期阻止保存，修正日期后允许继续', (tester) async {
      await _pumpApp(tester, fixture);
      await _openDraft(tester, '12月20日买菜35块');

      expect(find.text('这个日期在未来，请检查日期。'), findsAtLeastNWidgets(1));
      expect(_saveButton(tester).onPressed, isNull);

      await _scrollEditorFieldIntoView(tester, const Key('editor-date-field'));
      await tester.enterText(
        find.byKey(const Key('editor-date-field')),
        '2026-08-31',
      );
      await tester.pumpAndSettle();

      expect(_saveButton(tester).onPressed, isNotNull);
    });

    testWidgets('多金额输入提示拆成两笔且不自动写入', (tester) async {
      await _pumpApp(tester, fixture);
      await _openDraft(tester, '买菜35又打车20');

      expect(find.textContaining('识别到多个金额'), findsOneWidget);
      expect(find.byKey(const Key('split-manually')), findsOneWidget);
      expect(find.text('请把多笔账拆成一笔后再保存。'), findsOneWidget);
      expect(_saveButton(tester).onPressed, isNull);
      expect(fixture.controller.visibleEntries, isEmpty);
    });

    testWidgets('未保存草稿离开时弹出防丢失确认', (tester) async {
      await _pumpApp(tester, fixture);
      await _openDraft(tester, '35块买菜');

      await tester.ensureVisible(find.byKey(const Key('editor-note-field')));
      await tester.enterText(
        find.byKey(const Key('editor-note-field')),
        '晚上买菜',
      );
      await tester.tap(find.byKey(const Key('editor-back')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('discard-dialog')), findsOneWidget);
      expect(find.text('继续编辑'), findsOneWidget);
      expect(find.text('放弃更改'), findsOneWidget);

      await tester.tap(find.byKey(const Key('continue-editing')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('editor-page')), findsOneWidget);

      await tester.tap(find.byKey(const Key('editor-back')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('discard-changes')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('editor-page')), findsNothing);
      expect(fixture.controller.visibleEntries, isEmpty);
    });

    testWidgets('批量确认页返回后清空批量草稿', (tester) async {
      await _pumpApp(tester, fixture);
      await _openBatchDraft(tester, '买菜35元\n加油300元');

      expect(find.byKey(const Key('batch-confirm-page')), findsOneWidget);
      expect(fixture.controller.batchDraft, isNotNull);

      await tester.tap(find.byKey(const Key('batch-back')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('batch-confirm-page')), findsNothing);
      expect(fixture.controller.batchDraft, isNull);
      expect(find.byKey(const Key('home-page')), findsOneWidget);
    });

    testWidgets('列表刷新失败显示错误，重试后回到空状态', (tester) async {
      await _pumpApp(tester, fixture);
      fixture.controller.failNextRefreshForTest();
      await fixture.controller.refresh();
      await tester.pumpAndSettle();
      await _openTransactionsTab(tester);

      expect(find.byKey(const Key('transactions-error-state')), findsOneWidget);
      await _tapAndWaitForControllerIdle(
        tester,
        find.byKey(const Key('retry-list-load')),
        fixture.controller,
      );
      expect(find.byKey(const Key('transactions-empty-state')), findsOneWidget);
    });
  });

  group('单条真实账目 UI', () {
    late int entryId;

    setUp(() async {
      await fixture.reset();
      entryId = (await fixture.seed()).id;
      await fixture.controller.refresh();
    });

    testWidgets('编辑页保存校验阻止无效金额', (tester) async {
      await _pumpApp(tester, fixture);
      await _openTransactionsTab(tester);
      await tester.tap(_visibleTransactionFinder(entryId));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('editor-amount-field')), '0');
      await tester.pumpAndSettle();

      expect(find.text('请输入大于 0 的金额。'), findsOneWidget);
      expect(_saveButton(tester).onPressed, isNull);
      expect(fixture.controller.visibleEntries.single.amountCents, 3500);
    });

    testWidgets('删除使用软删除，撤销后恢复并联动统计', (tester) async {
      await _pumpApp(tester, fixture);
      await _openTransactionsTab(tester);
      await tester.tap(_visibleTransactionFinder(entryId));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('editor-page')), findsOneWidget);

      await _scrollEditorToBottom(tester);
      await tester.ensureVisible(find.byKey(const Key('delete-entry-button')));
      await tester.tap(find.byKey(const Key('delete-entry-button')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('delete-confirmation-dialog')),
        findsOneWidget,
      );

      await _confirmDeleteAndWait(tester, fixture.controller, entryId);

      expect(find.text('已删除这笔账'), findsAtLeastNWidgets(1));
      expect(
        find.byKey(const Key('undo-delete-action')),
        findsAtLeastNWidgets(1),
      );
      expect(find.byKey(Key('transaction-$entryId')), findsNothing);
      expect(fixture.controller.todayExpenseCents, 0);

      await _tapAndWaitForControllerIdle(
        tester,
        find.byKey(const Key('undo-delete-action')).first,
        fixture.controller,
      );
      expect(find.byKey(Key('transaction-$entryId')), findsAtLeastNWidgets(1));
      expect(fixture.controller.todayExpenseCents, 3500);

      await tester.tap(_visibleTransactionFinder(entryId));
      await tester.pumpAndSettle();
      await _scrollEditorToBottom(tester);
      await tester.ensureVisible(find.byKey(const Key('delete-entry-button')));
      await tester.tap(find.byKey(const Key('delete-entry-button')));
      await tester.pumpAndSettle();
      await _confirmDeleteAndWait(tester, fixture.controller, entryId);
      await tester.pump(const Duration(seconds: 11));

      expect(find.byKey(const Key('undo-delete-action')), findsNothing);
      expect(fixture.controller.visibleEntries, isEmpty);
    });
  });

  group('列表错误 UI', () {
    setUp(() async {
      await fixture.reset();
    });

    testWidgets('列表刷新失败显示错误，重试后回到空状态', (tester) async {
      await _pumpApp(tester, fixture);
      fixture.controller.failNextRefreshForTest();
      await fixture.controller.refresh();
      await tester.pumpAndSettle();
      await _openTransactionsTab(tester);

      expect(find.byKey(const Key('transactions-error-state')), findsOneWidget);
      await _tapAndWaitForControllerIdle(
        tester,
        find.byKey(const Key('retry-list-load')),
        fixture.controller,
      );
      expect(find.byKey(const Key('transactions-empty-state')), findsOneWidget);
    });
  });

  group('真实分页 UI', () {
    setUp(() async {
      await fixture.reset();
      await _seedMany(fixture, 55);
      await fixture.controller.refresh();
    });

    testWidgets('账单列表真实分页可加载超过 50 条', (tester) async {
      await _pumpApp(tester, fixture);
      await _openTransactionsTab(tester);

      expect(fixture.controller.visibleEntries, hasLength(20));
      await _scrollTransactionsToLoadMore(tester);

      await tester.tap(find.byKey(const Key('load-more-button')));
      await tester.pump();
      expect(find.byKey(const Key('load-more-loading')), findsOneWidget);
      await tester.runAsync(
        () => _waitForControllerIdleInRealAsync(fixture.controller),
      );
      await tester.pumpAndSettle();
      expect(fixture.controller.visibleEntries, hasLength(40));

      await _scrollTransactionsToLoadMore(tester);
      await _tapAndWaitForControllerIdle(
        tester,
        find.byKey(const Key('load-more-button')),
        fixture.controller,
      );

      expect(fixture.controller.visibleEntries, hasLength(55));
      await _scrollTransactionsToEnd(tester);
      expect(find.byKey(const Key('load-more-end')), findsOneWidget);
    });
  });

  group('分页失败 UI', () {
    setUp(() async {
      await fixture.reset();
      await _seedMany(fixture, 45);
      await fixture.controller.refresh();
    });

    testWidgets('加载更多失败时显示重试并恢复真实分页', (tester) async {
      await _pumpApp(tester, fixture);
      fixture.controller.failNextLoadMoreForTest();
      await _openTransactionsTab(tester);
      await _scrollTransactionsToLoadMore(tester);

      await _tapAndWaitForControllerIdle(
        tester,
        find.byKey(const Key('load-more-button')),
        fixture.controller,
      );
      expect(find.byKey(const Key('load-more-retry')), findsOneWidget);

      await _tapAndWaitForControllerIdle(
        tester,
        find.byKey(const Key('load-more-retry')),
        fixture.controller,
      );
      expect(fixture.controller.visibleEntries, hasLength(40));
      await _scrollTransactionsToLoadMore(tester);
      expect(find.byKey(const Key('load-more-button')), findsOneWidget);
    });
  });

  group('搜索 UI', () {
    late int fuelCurrentMonthId;
    late int fuelLastMonthId;
    late int groceryCurrentMonthId;

    setUp(() async {
      await fixture.reset();

      fixture.clock.set(DateTime(2026, 8, 31, 8));
      fuelCurrentMonthId = (await fixture.seed(
        amountCents: 30000,
        category: 'vehicle_fuel',
        note: '中国石化',
        originalText: '中国石化300',
      )).id;

      fixture.clock.set(DateTime(2026, 7, 31, 8));
      fuelLastMonthId = (await fixture.seed(
        amountCents: 28000,
        category: 'vehicle_fuel',
        note: '中国石化',
        originalText: '中国石化280',
        transactionDate: '2026-07-31',
      )).id;

      fixture.clock.set(DateTime(2026, 8, 31, 8));
      groceryCurrentMonthId = (await fixture.seed(
        amountCents: 4200,
        category: 'groceries_food',
        note: '超市购物',
        originalText: '超市购物42',
      )).id;

      await fixture.controller.refresh();
    });

    testWidgets('首页搜索框支持本月加油并可清除', (tester) async {
      await _pumpApp(tester, fixture);

      await tester.enterText(find.byKey(const Key('search-input')), '本月加油');
      await _tapAndWaitForSearchIdle(
        tester,
        find.byKey(const Key('search-submit')),
        fixture.controller,
      );

      expect(find.text('找到 1 笔账目。'), findsOneWidget);
      expect(find.byKey(const Key('search-empty-state')), findsNothing);

      final homePage = find.byKey(const Key('home-page'));
      expect(
        find.descendant(
          of: homePage,
          matching: find.byKey(Key('transaction-$fuelCurrentMonthId')),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: homePage,
          matching: find.byKey(Key('transaction-$fuelLastMonthId')),
        ),
        findsNothing,
      );

      await tester.tap(find.byKey(const Key('search-clear')));
      await tester.pumpAndSettle();

      expect(find.text('最近账目'), findsOneWidget);
      expect(
        find.descendant(
          of: homePage,
          matching: find.byKey(Key('transaction-$groceryCurrentMonthId')),
        ),
        findsOneWidget,
      );
    });

    testWidgets('首页把最近账目放在搜索和快速记账之前', (tester) async {
      await tester.pumpWidget(SmartLedgerApp(controller: fixture.controller));
      await tester.pump(const Duration(milliseconds: 100));

      final recentHeader = tester.getTopLeft(find.text('最近账目'));
      final searchInput = tester.getTopLeft(
        find.byKey(const Key('search-input')),
      );
      final quickInput = tester.getTopLeft(
        find.byKey(const Key('quick-input')),
      );

      expect(recentHeader.dy, lessThan(searchInput.dy));
      expect(searchInput.dy, lessThan(quickInput.dy));
    });
  });

  group('备份 UI', () {
    setUp(() async {
      await fixture.reset();
    });

    testWidgets('备份菜单提供导出和恢复入口', (tester) async {
      await _pumpApp(tester, fixture);

      await tester.tap(find.byKey(const Key('backup-menu')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('backup-export-action')), findsOneWidget);
      expect(find.byKey(const Key('backup-restore-action')), findsOneWidget);
    });
  });
}

Future<void> _pumpApp(WidgetTester tester, TestLedgerFixture fixture) async {
  await tester.pumpWidget(SmartLedgerApp(controller: fixture.controller));
  await tester.pumpAndSettle();
}

Future<void> _openDraft(WidgetTester tester, String text) async {
  await _enterVisibleText(tester, find.byKey(const Key('quick-input')), text);
  await _tapVisible(tester, find.byKey(const Key('quick-submit')));
  await tester.pumpAndSettle();
}

Future<void> _openBatchDraft(WidgetTester tester, String text) async {
  await _enterVisibleText(tester, find.byKey(const Key('quick-input')), text);
  await _tapVisible(tester, find.byKey(const Key('batch-entry-button')));
  await tester.pumpAndSettle();
}

Future<void> _openTransactionsTab(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.receipt_long_outlined));
  await tester.pumpAndSettle();
}

Future<void> _scrollEditorToBottom(WidgetTester tester) async {
  final page = find.byKey(const Key('editor-page'));
  for (var attempt = 0; attempt < 4; attempt += 1) {
    if (find.byKey(const Key('delete-entry-button')).evaluate().isNotEmpty) {
      return;
    }
    await tester.drag(page, const Offset(0, -700));
    await tester.pumpAndSettle();
  }
}

Future<void> _scrollEditorFieldIntoView(
  WidgetTester tester,
  Key key, {
  double delta = -500,
}) async {
  final page = find.byKey(const Key('editor-page'));
  final field = find.byKey(key);

  for (var attempt = 0; attempt < 12; attempt += 1) {
    if (field.evaluate().isNotEmpty) {
      await tester.ensureVisible(field);
      await tester.pumpAndSettle();
      return;
    }
    await tester.drag(page, Offset(0, delta));
    await tester.pumpAndSettle();
  }

  fail('编辑字段未构建: $key');
}

Finder _visibleTransactionFinder(int entryId) {
  return find.descendant(
    of: find.byKey(const Key('transactions-page')),
    matching: find.byKey(Key('transaction-$entryId')),
  );
}

Future<void> _seedMany(TestLedgerFixture fixture, int count) async {
  for (var index = 0; index < count; index += 1) {
    fixture.clock.set(DateTime(2026, 8, 31, 8, 0, index));
    await fixture.seed(
      amountCents: 1000 + index,
      note: '分页测试 $index',
      originalText: '分页测试 $index',
    );
  }
  fixture.clock.set(DateTime(2026, 8, 31, 10, 30));
}

Future<void> _waitForControllerIdleInRealAsync(
  LedgerUiController controller,
) async {
  for (var attempt = 0; attempt < 80; attempt += 1) {
    if (!controller.isBusy) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  fail('Controller 在真实异步等待窗口内未完成异步操作');
}

Future<void> _tapAndWaitForControllerIdle(
  WidgetTester tester,
  Finder finder,
  LedgerUiController controller,
) async {
  await tester.runAsync(() async {
    await tester.tap(finder);
    await _waitForControllerIdleInRealAsync(controller);
  });
  await tester.pumpAndSettle();
}

Future<void> _tapAndWaitForSearchIdle(
  WidgetTester tester,
  Finder finder,
  LedgerUiController controller,
) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.runAsync(() async {
    await tester.tap(finder);
    await _waitForControllerSearchIdleInRealAsync(controller);
  });
  await tester.pumpAndSettle();
}

Future<void> _enterVisibleText(
  WidgetTester tester,
  Finder finder,
  String text,
) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.enterText(finder, text);
}

Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
}

Future<void> _confirmDeleteAndWait(
  WidgetTester tester,
  LedgerUiController controller,
  int deletedEntryId,
) async {
  await tester.tap(find.byKey(const Key('confirm-delete')));
  await tester.pumpAndSettle();
  await tester.runAsync(() async {
    await _waitForDeleteAppliedInRealAsync(controller, deletedEntryId);
    await Future<void>.delayed(const Duration(milliseconds: 400));
  });
  for (var attempt = 0; attempt < 20; attempt += 1) {
    await tester.pump(const Duration(milliseconds: 50));
    await tester.runAsync(() async {
      await Future<void>.delayed(Duration.zero);
    });
    final editorRouteIsVisible =
        find.byKey(const Key('editor-page')).evaluate().isNotEmpty ||
        find.byKey(const Key('editor-operation-result')).evaluate().isNotEmpty;
    if (!editorRouteIsVisible) {
      await tester.pumpAndSettle();
      return;
    }
  }
  fail(
    '删除后编辑页未退出，busy=${controller.isBusy} '
    'statisticsBusy=${controller.isStatisticsBusy} '
    'budgetBusy=${controller.isBudgetBusy} '
    'feedback=${controller.feedbackMessage}',
  );
}

Future<void> _waitForDeleteAppliedInRealAsync(
  LedgerUiController controller,
  int deletedEntryId,
) async {
  for (var attempt = 0; attempt < 80; attempt += 1) {
    final removed = controller.visibleEntries.every(
      (entry) => entry.id != deletedEntryId,
    );
    final summaryUpdated = controller.todayExpenseCents == 0;
    if (removed && summaryUpdated) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  fail('删除后的控制器状态未在真实异步等待窗口内收敛');
}

Future<void> _waitForControllerSearchIdleInRealAsync(
  LedgerUiController controller,
) async {
  for (var attempt = 0; attempt < 80; attempt += 1) {
    if (!controller.isSearching) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  fail('Controller 在真实异步等待窗口内未完成搜索操作');
}

Future<void> _scrollTransactionsToLoadMore(WidgetTester tester) async {
  final loadMore = find.byKey(const Key('load-more-button'));
  final page = find.byKey(const Key('transactions-page'));
  for (
    var attempt = 0;
    attempt < 20 && loadMore.evaluate().isEmpty;
    attempt += 1
  ) {
    await tester.drag(page, const Offset(0, -500));
    await tester.pumpAndSettle();
  }
}

Future<void> _scrollTransactionsToEnd(WidgetTester tester) async {
  final end = find.byKey(const Key('load-more-end'));
  final page = find.byKey(const Key('transactions-page'));
  for (var attempt = 0; attempt < 20 && end.evaluate().isEmpty; attempt += 1) {
    await tester.drag(page, const Offset(0, -500));
    await tester.pumpAndSettle();
  }
}

FilledButton _saveButton(WidgetTester tester) {
  return tester.widget<FilledButton>(find.byKey(const Key('editor-save')));
}

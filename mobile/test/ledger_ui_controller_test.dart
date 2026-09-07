import 'package:flutter_test/flutter_test.dart';
import 'package:smartledger/domain/models/transaction_type.dart';
import 'package:smartledger/ui/ledger_ui_controller.dart';

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

  test('本地商户分类会进入现有确认流程而不是静默入库', () {
    final prepared = fixture.controller.prepareDraftFromInput('中国石化300元');

    expect(prepared, isTrue);
    expect(fixture.controller.draft?.amountText, '300.00');
    expect(fixture.controller.draft?.type, TransactionType.expense);
    expect(fixture.controller.draft?.category, 'vehicle_fuel');
    expect(
      fixture.controller.draft?.issues.any(
        (issue) => issue.code == 'LOCAL_CLASSIFICATION_SUGGESTION',
      ),
      isTrue,
    );
    expect(fixture.controller.canSaveDraft, isFalse);
    expect(fixture.controller.validationMessage, contains('待确认'));
  });

  test('写入成功但刷新失败仍视为成功且草稿已清除', () async {
    expect(fixture.controller.prepareDraftFromInput('35块买菜'), isTrue);
    fixture.controller.failNextRefreshForTest();

    final saved = await fixture.controller.saveDraft();

    expect(saved, isTrue);
    expect(
      fixture.controller.transactionSaveStatus,
      LedgerTransactionSaveStatus.savedWithRefreshFailure,
    );
    expect(fixture.controller.draft, isNull);
    expect(fixture.controller.feedbackMessage, contains('已保存，但列表刷新失败'));
    expect(await fixture.repository.list(), hasLength(1));
    expect(await fixture.controller.saveDraft(), isFalse);
  });

  test('批量保存完成后释放忙状态并只写入一次', () async {
    expect(
      fixture.controller.prepareBatchDraftFromInput('买菜35元\n加油300元'),
      isTrue,
    );
    final batch = fixture.controller.batchDraft;
    expect(batch, isNotNull);

    final saved = await fixture.controller.saveBatchTransactions(
      batch!.transactionsToSave,
    );

    expect(saved, isTrue);
    expect(
      fixture.controller.transactionSaveStatus,
      LedgerTransactionSaveStatus.saved,
    );
    expect(fixture.controller.isBusy, isFalse);
    expect(fixture.controller.batchDraft, isNull);
    expect(await fixture.repository.list(), hasLength(2));
  });

  test('批量写入成功但刷新失败仍视为成功且不保留批量草稿', () async {
    expect(
      fixture.controller.prepareBatchDraftFromInput('买菜35元\n加油300元'),
      isTrue,
    );
    final batch = fixture.controller.batchDraft;
    expect(batch, isNotNull);
    fixture.controller.failNextRefreshForTest();

    final saved = await fixture.controller.saveBatchTransactions(
      batch!.transactionsToSave,
    );

    expect(saved, isTrue);
    expect(
      fixture.controller.transactionSaveStatus,
      LedgerTransactionSaveStatus.savedWithRefreshFailure,
    );
    expect(fixture.controller.batchDraft, isNull);
    expect(await fixture.repository.list(), hasLength(2));
  });

  test('保存后统计刷新失败会标记为刷新失败而不是伪装成功', () async {
    await fixture.controller.refreshStatistics();

    fixture.controller.startCreateBlank();
    fixture.controller.updateAmountText('12.00');
    fixture.controller.updateType(TransactionType.expense);
    fixture.controller.updateCategory('dining');
    fixture.controller.failNextStatisticsRefreshForTest();

    expect(await fixture.controller.saveDraft(), isTrue);
    expect(
      fixture.controller.transactionSaveStatus,
      LedgerTransactionSaveStatus.savedWithRefreshFailure,
    );
    expect(fixture.controller.statisticsError, isNotNull);
    expect(fixture.controller.draft, isNull);
    expect(await fixture.repository.list(), hasLength(1));
  });

  test('统计刷新在首页忙碌期间触发不会被丢弃', () async {
    final refresh = fixture.controller.refresh();
    final statisticsRefresh = fixture.controller.refreshStatistics();

    await Future.wait([refresh, statisticsRefresh]);

    expect(fixture.controller.statisticsSummary, isNotNull);
    expect(fixture.controller.isStatisticsBusy, isFalse);
  });

  test('统计初始化加载完整时间序列并按时间正序排列', () async {
    await fixture.seed(
      amountCents: 7000,
      category: 'dining',
      transactionDate: '2026-01-15',
    );
    await fixture.seed(
      amountCents: 3000,
      category: 'groceries_food',
      transactionDate: '2026-08-31',
    );
    await fixture.seed(
      amountCents: 5000,
      type: TransactionType.income,
      category: 'salary',
      transactionDate: '2026-08-31',
    );

    await fixture.controller.refreshStatistics();

    final monthly = fixture.controller.monthlyStatisticsTimeSeries;
    final yearly = fixture.controller.yearlyStatisticsTimeSeries;
    expect(monthly, isNotNull);
    expect(monthly!.buckets, hasLength(31));
    expect(monthly.buckets.first.key, '2026-08-01');
    expect(monthly.buckets.last.key, '2026-08-31');
    expect(monthly.buckets.last.expenseTotalCents, 3000);
    expect(monthly.buckets.last.incomeTotalCents, 5000);
    expect(yearly, isNotNull);
    expect(yearly!.buckets, hasLength(12));
    expect(yearly.buckets.first.key, '2026-01');
    expect(yearly.buckets.last.key, '2026-12');
    expect(yearly.buckets.first.expenseTotalCents, 7000);
    expect(yearly.buckets[7].expenseTotalCents, 3000);
  });

  test('保存、编辑、删除和撤销后已初始化统计会刷新', () async {
    await fixture.controller.refreshStatistics();

    fixture.controller.startCreateBlank();
    fixture.controller.updateAmountText('12.00');
    fixture.controller.updateType(TransactionType.expense);
    fixture.controller.updateCategory('dining');
    expect(await fixture.controller.saveDraft(), isTrue);
    expect(
      fixture
          .controller
          .monthlyStatisticsTimeSeries!
          .buckets
          .last
          .expenseTotalCents,
      1200,
    );

    final savedEntry = fixture.controller.visibleEntries.single;
    fixture.controller.startEditing(savedEntry);
    fixture.controller.updateAmountText('20.00');
    expect(await fixture.controller.saveDraft(), isTrue);
    expect(
      fixture
          .controller
          .monthlyStatisticsTimeSeries!
          .buckets
          .last
          .expenseTotalCents,
      2000,
    );

    fixture.controller.startEditing(fixture.controller.visibleEntries.single);
    expect(await fixture.controller.deleteCurrentEntry(), isTrue);
    expect(
      fixture
          .controller
          .monthlyStatisticsTimeSeries!
          .buckets
          .last
          .expenseTotalCents,
      0,
    );

    expect(await fixture.controller.undoDelete(), isTrue);
    expect(
      fixture
          .controller
          .monthlyStatisticsTimeSeries!
          .buckets
          .last
          .expenseTotalCents,
      2000,
    );
  });
}

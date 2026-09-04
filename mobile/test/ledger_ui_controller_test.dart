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

  test('统计刷新在首页忙碌期间触发不会被丢弃', () async {
    final refresh = fixture.controller.refresh();
    final statisticsRefresh = fixture.controller.refreshStatistics();

    await Future.wait([refresh, statisticsRefresh]);

    expect(fixture.controller.statisticsSummary, isNotNull);
    expect(fixture.controller.isStatisticsBusy, isFalse);
  });
}

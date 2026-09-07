import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartledger/app/smart_ledger_app.dart';
import 'package:smartledger/data/import/import_coordinator.dart';
import 'package:smartledger/data/import/import_file_picker.dart';
import 'package:smartledger/domain/import/import_contract.dart';
import 'package:smartledger/domain/models/ledger_transaction.dart';
import 'package:smartledger/ui/import/import_confirm_page.dart';
import 'package:smartledger/ui/import/import_entry_page.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'test_support.dart';

void main() {
  sqfliteFfiInit();

  late TestLedgerFixture fixture;

  setUpAll(() async {
    fixture = await TestLedgerFixture.create();
  });

  setUp(() async {
    await fixture.reset();
  });

  tearDownAll(() async {
    await fixture.dispose();
  });

  testWidgets('主 App 导入按钮打开来源选择入口', (tester) async {
    await tester.pumpWidget(SmartLedgerApp(controller: fixture.controller));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('open-accounting-tools')), findsOneWidget);
    await tester.tap(find.byKey(const Key('open-accounting-tools')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('accounting-tool-import')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('import-entry-page')), findsOneWidget);
    expect(find.text('微信账单'), findsOneWidget);
    expect(find.text('支付宝账单'), findsOneWidget);
  });

  testWidgets('切换支付宝来源后选择文件进入现有确认页并显示统计', (tester) async {
    final picker = _FakeImportFilePicker([_alipayFile()]);
    final coordinator = ImportCoordinator(
      repository: fixture.repository,
      filePicker: picker,
    );

    await tester.pumpWidget(
      _testApp(ImportEntryPage(coordinator: coordinator)),
    );
    await tester.tap(find.text('支付宝账单'));
    await tester.pump();
    await _tapImportFileAndWait(tester, find.byType(ImportConfirmPage));

    expect(find.byType(ImportConfirmPage), findsOneWidget);
    expect(find.byKey(const Key('import-source-file-name')), findsOneWidget);
    expect(find.text('支付宝账单.csv'), findsOneWidget);
    expect(find.text('支付宝 CSV 导入'), findsOneWidget);
    expect(
      find.byKey(const Key('import-count-candidate-value')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('import-count-blocking-value')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('import-row-blocking-4')), findsOneWidget);
    expect(find.text('金额格式无法转换为大于 0 的整数分。'), findsOneWidget);
    await tester.runAsync(() async {
      expect(await fixture.repository.list(), isEmpty);
    });
  });

  testWidgets('取消选择显示未改账状态，解析失败可以重试', (tester) async {
    final picker = _FakeImportFilePicker([
      null,
      PickedImportFile(fileName: '微信账单.txt', bytes: utf8.encode('内容')),
    ]);
    final coordinator = ImportCoordinator(
      repository: fixture.repository,
      filePicker: picker,
    );

    await tester.pumpWidget(
      _testApp(
        ImportEntryPage(
          coordinator: coordinator,
          onBatchSaveFailureMessage: () => '已记账旧操作反馈。',
        ),
      ),
    );
    await _tapImportFileAndWait(
      tester,
      find.byKey(const Key('import-entry-status')),
    );
    expect(find.text('已取消选择，账本未修改。'), findsOneWidget);
    await tester.runAsync(() async {
      expect(await fixture.repository.list(), isEmpty);
    });

    await _tapImportFileAndWait(
      tester,
      find.byKey(const Key('import-entry-error')),
    );
    expect(find.byKey(const Key('import-entry-error')), findsOneWidget);
    expect(find.text('请选择 CSV 文件。'), findsOneWidget);
    expect(find.byKey(const Key('import-entry-retry')), findsOneWidget);
  });

  testWidgets('导入保存失败使用导入本地反馈，不复用旧操作反馈', (tester) async {
    final coordinator = ImportCoordinator(
      repository: fixture.repository,
      filePicker: _FakeImportFilePicker([_wechatFile()]),
    );

    await tester.pumpWidget(
      _testApp(
        ImportEntryPage(
          coordinator: coordinator,
          onSaveBatch: (_, _) async => false,
          onBatchSaveFailureMessage: () => '已记账旧操作反馈。',
        ),
      ),
    );
    await _tapImportFileAndWait(tester, find.byType(ImportConfirmPage));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('import-row-blocking-1')), findsOneWidget);
    await tester.tap(find.byKey(const Key('import-exclude-row-1')));
    await tester.pump();
    await tester.scrollUntilVisible(
      find.byKey(const Key('import-confirm-row-2')),
      160,
    );
    await tester.drag(
      find.byKey(const Key('import-page')),
      const Offset(0, -80),
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('import-confirm-row-2')));
    await tester.pump();
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('import-submit')))
          .onPressed,
      isNotNull,
    );
    await tester.tap(find.byKey(const Key('import-submit')));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('import-submit-error')), findsOneWidget);
    expect(find.text('导入保存失败，账本未修改，请重试。'), findsOneWidget);
    expect(find.text('已记账旧操作反馈。'), findsNothing);
    await tester.runAsync(() async {
      expect(await fixture.repository.list(), isEmpty);
    });
  });

  testWidgets('疑似重复账目在确认页可观察', (tester) async {
    final parserCoordinator = ImportCoordinator(repository: fixture.repository);
    final file = _alipayFile();
    await tester.runAsync(() async {
      final parsed = await parserCoordinator.parsePickedFile(
        ImportSourceType.alipayCsv,
        file,
      );
      final existingTransaction = parsed.candidateRows
          .map((row) => row.toNewLedgerTransaction())
          .whereType<NewLedgerTransaction>()
          .single;
      await fixture.repository.create(existingTransaction);
    });

    final coordinator = ImportCoordinator(
      repository: fixture.repository,
      filePicker: _FakeImportFilePicker([file]),
    );
    await tester.pumpWidget(
      _testApp(ImportEntryPage(coordinator: coordinator)),
    );
    await tester.tap(find.text('支付宝账单'));
    await tester.pump();
    await _tapImportFileAndWait(tester, find.byType(ImportConfirmPage));
    await tester.pumpAndSettle();

    final duplicateRow = find.byKey(const Key('import-row-duplicate-3'));
    final duplicateCount = tester.widget<Text>(
      find.byKey(const Key('import-count-duplicate-value')),
    );
    expect(duplicateCount.data, '1 条');
    for (
      var attempt = 0;
      attempt < 8 && duplicateRow.evaluate().isEmpty;
      attempt += 1
    ) {
      await tester.drag(
        find.byKey(const Key('import-page')),
        const Offset(0, -220),
      );
      await tester.pump();
    }
    expect(duplicateRow, findsOneWidget);
    expect(
      find.byKey(const Key('import-row-duplicate-message-3')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('import-duplicate-notice')), findsOneWidget);
    await tester.runAsync(() async {
      expect(await fixture.repository.list(), hasLength(1));
    });
  });
}

Future<void> _tapImportFileAndWait(
  WidgetTester tester,
  Finder completion,
) async {
  await tester.runAsync(() async {
    await tester.tap(find.byKey(const Key('import-pick-file')));
  });

  for (var attempt = 0; attempt < 80; attempt += 1) {
    await tester.pump(const Duration(milliseconds: 50));
    if (completion.evaluate().isNotEmpty) {
      return;
    }
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 25));
    });
  }

  fail('导入文件操作未在真实异步等待窗口内完成');
}

Widget _testApp(Widget child) {
  return MaterialApp(theme: ThemeData(useMaterial3: true), home: child);
}

final class _FakeImportFilePicker implements ImportFilePicker {
  _FakeImportFilePicker(Iterable<PickedImportFile?> responses)
    : _responses = [...responses];

  final List<PickedImportFile?> _responses;

  @override
  Future<PickedImportFile?> pickCsv() async {
    if (_responses.isEmpty) {
      return null;
    }
    return _responses.removeAt(0);
  }
}

PickedImportFile _alipayFile() {
  const csv = '''支付宝交易记录明细
交易时间,交易分类,收/支,金额,交易对方,商品说明,交易订单号,资金状态
2026-08-31 12:30:00,餐饮,支出,35.00,星巴克,咖啡,ORDER-1,交易成功
2026-08-31 12:31:00,餐饮,支出,12.345,星巴克,咖啡,BAD-1,交易成功
''';
  return PickedImportFile(fileName: '支付宝账单.csv', bytes: utf8.encode(csv));
}

PickedImportFile _wechatFile() {
  const csv = '''交易时间,收支,交易对方,金额(元),当前状态
2026-08-31,支出,菜市场,35.00,交易成功
''';
  return PickedImportFile(fileName: '微信账单.csv', bytes: utf8.encode(csv));
}

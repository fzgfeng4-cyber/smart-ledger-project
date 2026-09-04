import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartledger/domain/import/import_contract.dart';
import 'package:smartledger/domain/models/ledger_transaction.dart';
import 'package:smartledger/domain/models/transaction_type.dart';
import 'package:smartledger/ui/import/import_confirm_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('逐行确认后才允许提交，并通过回调传出批次与交易', (tester) async {
    final batch = ImportDraftBatch(
      source: _source(),
      rows: [
        _candidate(lineNumber: 1),
        _candidate(
          lineNumber: 2,
          issues: const [
            ImportIssue(
              code: ImportIssueCodes.unknownMerchant,
              severity: ImportIssueSeverity.warning,
              field: 'merchant',
              message: '未识别交易对方，请核对备注和分类。',
            ),
          ],
        ),
      ],
    );
    ImportDraftBatch? submittedBatch;
    List<NewLedgerTransaction>? submittedTransactions;

    await tester.pumpWidget(
      _testApp(
        ImportConfirmPage(
          batch: batch,
          closeOnSuccess: false,
          onSubmit: (updatedBatch, transactions) async {
            submittedBatch = updatedBatch;
            submittedTransactions = transactions;
            return true;
          },
        ),
      ),
    );

    expect(find.byKey(const Key('import-source-file-name')), findsOneWidget);
    expect(find.text('微信支付账单.csv'), findsOneWidget);
    expect(
      find.byKey(const Key('import-count-candidate-value')),
      findsOneWidget,
    );
    expect(_summaryValue(tester, 'import-count-retained-value'), '2 条');
    expect(_summaryValue(tester, 'import-count-candidate-value'), '2 条');
    expect(_summaryValue(tester, 'import-count-confirmation-value'), '2 条');
    expect(find.byKey(const Key('import-row-raw-1')), findsOneWidget);
    expect(find.text('2026-08-31'), findsNWidgets(2));
    expect(find.text('¥35.00'), findsNWidgets(2));
    expect(find.text('支出'), findsNWidgets(2));
    expect(find.text('买菜/食品'), findsAtLeastNWidgets(2));

    expect(_submitButton(tester).onPressed, isNull);

    await tester.tap(find.byKey(const Key('import-confirm-row-1')));
    await tester.pump();
    expect(_summaryValue(tester, 'import-count-confirmation-value'), '1 条');
    expect(_submitButton(tester).onPressed, isNull);

    await tester.scrollUntilVisible(
      find.byKey(const Key('import-confirm-row-2')),
      160,
    );
    await tester.drag(
      find.byKey(const Key('import-page')),
      const Offset(0, -120),
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('import-confirm-row-2')));
    await tester.pump();
    expect(_submitButton(tester).onPressed, isNotNull);

    await tester.tap(find.byKey(const Key('import-submit')));
    await tester.pump();

    expect(submittedBatch, isNotNull);
    expect(submittedBatch!.canSubmit, isTrue);
    expect(submittedTransactions, hasLength(2));
    expect(submittedTransactions!.first.category, 'groceries_food');
  });

  testWidgets('排除异常行后允许提交，恢复异常行会重新关闭提交门禁', (tester) async {
    final batch = ImportDraftBatch(
      source: _source(),
      rows: [_candidate(lineNumber: 1), _blockingCandidate(lineNumber: 2)],
    );
    List<NewLedgerTransaction>? submittedTransactions;

    await tester.pumpWidget(
      _testApp(
        ImportConfirmPage(
          batch: batch,
          closeOnSuccess: false,
          onSubmit: (_, transactions) async {
            submittedTransactions = transactions;
            return true;
          },
        ),
      ),
    );

    expect(_submitButton(tester).onPressed, isNull);
    await tester.tap(find.byKey(const Key('import-confirm-row-1')));
    await tester.pump();
    expect(_submitButton(tester).onPressed, isNull);

    await tester.scrollUntilVisible(
      find.byKey(const Key('import-exclude-row-2')),
      160,
    );
    await tester.drag(
      find.byKey(const Key('import-page')),
      const Offset(0, -120),
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('import-exclude-row-2')));
    await tester.pump();
    expect(
      find.byKey(const Key('import-count-excluded-value')),
      findsOneWidget,
    );
    expect(_submitButton(tester).onPressed, isNotNull);

    await tester.scrollUntilVisible(
      find.byKey(const Key('import-restore-row-2')),
      160,
    );
    await tester.drag(
      find.byKey(const Key('import-page')),
      const Offset(0, -120),
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('import-restore-row-2')));
    await tester.pump();
    expect(_submitButton(tester).onPressed, isNull);

    await tester.scrollUntilVisible(
      find.byKey(const Key('import-exclude-row-2')),
      160,
    );
    await tester.drag(
      find.byKey(const Key('import-page')),
      const Offset(0, -120),
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('import-exclude-row-2')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('import-submit')));
    await tester.pump();

    expect(submittedTransactions, hasLength(1));
  });

  testWidgets('阻塞行不能确认，只能排除，且显示异常原因', (tester) async {
    final batch = ImportDraftBatch(
      source: _source(),
      rows: [_candidate(lineNumber: 1), _blockingCandidate(lineNumber: 2)],
    );

    await tester.pumpWidget(
      _testApp(
        ImportConfirmPage(
          batch: batch,
          closeOnSuccess: false,
          onSubmit: (_, _) async => true,
        ),
      ),
    );

    final confirmButton = tester.widget<OutlinedButton>(
      find.byKey(const Key('import-confirm-row-2')),
    );
    expect(confirmButton.onPressed, isNull);
    expect(find.byKey(const Key('import-row-blocking-2')), findsOneWidget);
    expect(find.text('金额格式无法转换为整数分。'), findsOneWidget);
    expect(
      tester.widget<OutlinedButton>(
        find.byKey(const Key('import-exclude-row-2')),
      ),
      isNotNull,
    );
    expect(_submitButton(tester).onPressed, isNull);
  });

  testWidgets('支持切换分类建议，切换后需要重新确认本行', (tester) async {
    final batch = ImportDraftBatch(
      source: _source(),
      rows: [
        _candidate(
          lineNumber: 1,
          suggestions: const [
            ImportCategorySuggestion(
              categoryCode: 'groceries_food',
              reason: '商户规则建议',
            ),
            ImportCategorySuggestion(categoryCode: 'dining', reason: '文本分类建议'),
          ],
        ),
      ],
    );
    ImportDraftBatch? changedBatch;
    List<NewLedgerTransaction>? submittedTransactions;

    await tester.pumpWidget(
      _testApp(
        ImportConfirmPage(
          batch: batch,
          closeOnSuccess: false,
          onBatchChanged: (updatedBatch) => changedBatch = updatedBatch,
          onSubmit: (_, transactions) async {
            submittedTransactions = transactions;
            return true;
          },
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('import-category-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('餐饮').last);
    await tester.pump();

    expect(changedBatch, isNotNull);
    expect(changedBatch!.findByLineNumber(1)!.suggestedCategoryCode, 'dining');
    expect(_submitButton(tester).onPressed, isNull);

    await tester.tap(find.byKey(const Key('import-confirm-row-1')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('import-submit')));
    await tester.pump();

    expect(submittedTransactions, hasLength(1));
    expect(submittedTransactions!.single.category, 'dining');
  });

  testWidgets('错误状态支持重试，空批次显示空状态', (tester) async {
    var retried = false;
    await tester.pumpWidget(
      _testApp(
        ImportConfirmPage(
          batch: ImportDraftBatch(source: _source(), rows: const []),
          errorMessage: '账单文件解析失败。',
          onRetry: () => retried = true,
          onSubmit: (_, _) async => true,
        ),
      ),
    );

    expect(find.byKey(const Key('import-error-state')), findsOneWidget);
    expect(find.text('账单文件解析失败。'), findsOneWidget);
    expect(find.byKey(const Key('import-submit')), findsNothing);
    await tester.tap(find.byKey(const Key('import-retry')));
    await tester.pump();
    expect(retried, isTrue);

    await tester.pumpWidget(
      _testApp(
        ImportConfirmPage(
          batch: ImportDraftBatch(source: _source(), rows: const []),
          onSubmit: (_, _) async => true,
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('import-empty-state')), findsOneWidget);
    expect(find.byKey(const Key('import-submit')), findsNothing);
  });

  testWidgets('窄屏显示不溢出且操作目标保持可用尺寸', (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(320, 640));

    final longRawText = '2026-08-31,微信支付,这是一条很长的原始账单内容用于验证窄屏换行不会撑破页面,35.00';
    final batch = ImportDraftBatch(
      source: _source(fileName: '一份很长的微信支付账单文件名称.csv'),
      rows: [
        ImportDraftRow(
          rawRow: ImportRawRow(lineNumber: 1, rawText: longRawText),
          transactionDate: '2026-08-31',
          amountCents: 3500,
          transactionType: TransactionType.expense,
          merchant: '菜市场',
          categorySuggestions: const [
            ImportCategorySuggestion(categoryCode: 'groceries_food'),
          ],
        ),
      ],
    );

    await tester.pumpWidget(
      _testApp(
        ImportConfirmPage(
          batch: batch,
          closeOnSuccess: false,
          onSubmit: (_, _) async => true,
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('import-page')), findsOneWidget);
    expect(find.byKey(const Key('import-source-file-name')), findsOneWidget);
    expect(find.byKey(const Key('import-confirm-row-1')), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const Key('import-submit'))).width,
      lessThanOrEqualTo(288),
    );
    expect(
      tester.getSize(find.byKey(const Key('import-confirm-row-1'))).height,
      greaterThanOrEqualTo(48),
    );
  });
}

Widget _testApp(Widget child) {
  return MaterialApp(theme: ThemeData(useMaterial3: true), home: child);
}

FilledButton _submitButton(WidgetTester tester) {
  return tester.widget<FilledButton>(find.byKey(const Key('import-submit')));
}

String _summaryValue(WidgetTester tester, String key) {
  return tester.widget<Text>(find.byKey(Key(key))).data!;
}

ImportFileSource _source({String fileName = '微信支付账单.csv'}) {
  return ImportFileSource(type: ImportSourceType.wechatCsv, fileName: fileName);
}

ImportDraftRow _candidate({
  required int lineNumber,
  List<ImportIssue> issues = const [],
  List<ImportCategorySuggestion>? suggestions,
}) {
  return ImportDraftRow(
    rawRow: ImportRawRow(
      lineNumber: lineNumber,
      rawText: '2026-08-31,$lineNumber,菜市场,35.00',
    ),
    transactionDate: '2026-08-31',
    amountCents: 3500,
    rawAmount: '35.00',
    transactionType: TransactionType.expense,
    merchant: '菜市场',
    categorySuggestions:
        suggestions ??
        const [ImportCategorySuggestion(categoryCode: 'groceries_food')],
    issues: issues,
  );
}

ImportDraftRow _blockingCandidate({required int lineNumber}) {
  return ImportDraftRow(
    rawRow: ImportRawRow(
      lineNumber: lineNumber,
      rawText: '2026-08-31,$lineNumber,菜市场,金额异常',
    ),
    transactionDate: '2026-08-31',
    amountCents: null,
    rawAmount: '金额异常',
    transactionType: TransactionType.expense,
    merchant: '菜市场',
    categorySuggestions: const [
      ImportCategorySuggestion(categoryCode: 'groceries_food'),
    ],
    issues: const [
      ImportIssue(
        code: ImportIssueCodes.invalidAmount,
        severity: ImportIssueSeverity.blocking,
        field: 'amount_cents',
        message: '金额格式无法转换为整数分。',
      ),
    ],
  );
}

import 'package:flutter_test/flutter_test.dart';
import 'package:smartledger/domain/import/import_contract.dart';
import 'package:smartledger/domain/models/transaction_type.dart';

void main() {
  test('有效导入候选保留来源和原始行，并映射为 NewLedgerTransaction', () {
    final row = ImportDraftRow(
      rawRow: const ImportRawRow(
        lineNumber: 7,
        rawText: '2026-08-31,消费,菜市场,35.00',
        fields: ['2026-08-31', '消费', '菜市场', '35.00'],
      ),
      transactionDate: '2026-08-31',
      amountCents: 3500,
      transactionType: TransactionType.expense,
      merchant: '菜市场',
      note: '晚餐食材',
      categorySuggestions: const [
        ImportCategorySuggestion(
          categoryCode: 'groceries_food',
          reason: '商户规则建议',
        ),
      ],
    );

    final transaction = row.toNewLedgerTransaction();

    expect(row.status, ImportRowStatus.candidate);
    expect(row.reviewState, ImportReviewState.pending);
    expect(row.rawRow.lineNumber, 7);
    expect(row.rawRow.rawText, contains('菜市场'));
    expect(transaction, isNotNull);
    expect(transaction!.amountCents, 3500);
    expect(transaction.type, TransactionType.expense);
    expect(transaction.category, 'groceries_food');
    expect(transaction.note, '菜市场 · 晚餐食材');
    expect(transaction.originalText, row.rawRow.rawText);
    expect(row.readyForSubmission, isFalse);
  });

  test('确认前不能生成可保存列表，确认后才进入批量保存候选', () {
    final row = _validRow(lineNumber: 3);
    final batch = ImportDraftBatch(
      source: const ImportFileSource(
        type: ImportSourceType.wechatCsv,
        fileName: '微信支付账单.csv',
      ),
      rows: [row],
    );

    expect(batch.rows, hasLength(1));
    expect(batch.canSubmit, isFalse);
    expect(batch.transactionsToSave, isEmpty);

    final confirmed = batch.confirm(3);

    expect(confirmed.rows.single.reviewState, ImportReviewState.confirmed);
    expect(confirmed.canSubmit, isTrue);
    expect(confirmed.transactionsToSave, hasLength(1));
    expect(confirmed.toBatchParseResult().canSubmit, isTrue);
  });

  test('缺日期和金额格式异常都是保留的阻塞行，不能转换', () {
    final missingDate = _validRow(lineNumber: 10)
        .copyWith(transactionDate: null);
    final invalidAmount = _validRow(lineNumber: 11).copyWith(
      amountCents: null,
      rawAmount: '12.345',
      issues: const [
        ImportIssue(
          code: ImportIssueCodes.invalidAmount,
          severity: ImportIssueSeverity.blocking,
          field: 'amount_cents',
          message: '金额格式无法转换为整数分。',
        ),
      ],
    );
    final batch = ImportDraftBatch(
      source: _source(),
      rows: [missingDate, invalidAmount],
    );

    expect(batch.rows, hasLength(2));
    expect(missingDate.hasBlockingIssues, isTrue);
    expect(missingDate.toNewLedgerTransaction(), isNull);
    expect(
      missingDate.issues.any(
        (issue) => issue.code == ImportIssueCodes.missingDate,
      ),
      isTrue,
    );
    expect(invalidAmount.hasBlockingIssues, isTrue);
    expect(invalidAmount.rawAmount, '12.345');
    expect(invalidAmount.toNewLedgerTransaction(), isNull);
    expect(batch.toBatchParseResult().blockingTransactions, hasLength(2));
    expect(batch.transactionsToSave, isEmpty);
  });

  test('收入可以成为待确认候选，退款和失败行保留为明确不可入账状态', () {
    final income = _validRow(
      lineNumber: 20,
      type: TransactionType.income,
      categoryCode: 'salary',
    );
    final refund = ImportDraftRow(
      rawRow: const ImportRawRow(
        lineNumber: 21,
        rawText: '2026-08-31,退款,商户,20.00',
      ),
      status: ImportRowStatus.refund,
      transactionDate: '2026-08-31',
      amountCents: 2000,
      transactionType: TransactionType.income,
      merchant: '商户',
    );
    final failed = ImportDraftRow(
      rawRow: const ImportRawRow(
        lineNumber: 22,
        rawText: '2026-08-31,交易失败,商户,20.00',
      ),
      status: ImportRowStatus.failed,
      transactionDate: '2026-08-31',
      amountCents: 2000,
      transactionType: TransactionType.expense,
      merchant: '商户',
    );

    expect(income.toNewLedgerTransaction()!.type, TransactionType.income);
    expect(refund.status, ImportRowStatus.refund);
    expect(refund.hasBlockingIssues, isTrue);
    expect(refund.toNewLedgerTransaction(), isNull);
    expect(
      refund.issues.any((issue) => issue.code == ImportIssueCodes.refundRow),
      isTrue,
    );
    expect(failed.status, ImportRowStatus.failed);
    expect(failed.hasBlockingIssues, isTrue);
    expect(failed.toNewLedgerTransaction(), isNull);
    expect(
      failed.issues.any((issue) => issue.code == ImportIssueCodes.failedRow),
      isTrue,
    );
  });

  test('未知商户和重复提示可观察，并要求确认而不是静默放行', () {
    final row = _validRow(
      lineNumber: 30,
      merchant: null,
      issues: const [
        ImportIssue(
          code: ImportIssueCodes.unknownMerchant,
          severity: ImportIssueSeverity.warning,
          field: 'merchant',
          message: '未识别交易对方，请核对备注和分类。',
        ),
      ],
      duplicateNotice: const ImportDuplicateNotice(
        message: '发现金额、日期和分类相同的历史账目。',
        matchingTransactionId: 42,
        matchKey: '2026-08-31|3500|expense|groceries_food',
      ),
    );
    final batch = ImportDraftBatch(source: _source(), rows: [row]);
    final adapted = batch.toBatchParseResult().transactions.single;

    expect(row.toNewLedgerTransaction(), isNotNull);
    expect(row.duplicateNotice, isNotNull);
    expect(
      row.issues.any(
        (issue) => issue.code == ImportIssueCodes.duplicateCandidate,
      ),
      isTrue,
    );
    expect(row.readyForSubmission, isFalse);
    expect(adapted.requiresConfirmation, isTrue);
    expect(adapted.parseResult.issues, isNotEmpty);
    expect(batch.canSubmit, isFalse);
    expect(batch.confirm(30).canSubmit, isTrue);
  });

  test('空行和未知行不会从批次中消失，且必须先排除才能提交其他有效行', () {
    final empty = ImportDraftRow(
      rawRow: ImportRawRow(lineNumber: 40, rawText: ''),
      status: ImportRowStatus.empty,
    );
    final unknown = ImportDraftRow(
      rawRow: ImportRawRow(lineNumber: 41, rawText: '无法识别的说明行'),
      status: ImportRowStatus.unknown,
    );
    final valid = _validRow(lineNumber: 42);
    final batch = ImportDraftBatch(
      source: _source(),
      rows: [empty, unknown, valid],
    );

    expect(batch.rows, hasLength(3));
    expect(batch.emptyRows.single.rawRow.lineNumber, 40);
    expect(batch.unknownRows.single.rawRow.lineNumber, 41);
    expect(batch.toBatchParseResult().transactions, hasLength(3));
    expect(batch.canSubmit, isFalse);

    final ready = batch.exclude(40).exclude(41).confirm(42);

    expect(ready.rows, hasLength(3));
    expect(ready.excludedRows.map((row) => row.rawRow.lineNumber), [40, 41]);
    expect(ready.transactionsToSave, hasLength(1));
    expect(ready.toBatchParseResult().canSubmit, isTrue);
  });

  test('导入行和批次的操作保持不可变', () {
    final row = _validRow(lineNumber: 50);
    final batch = ImportDraftBatch(source: _source(), rows: [row]);

    final excluded = batch.exclude(50);

    expect(batch.rows.single.reviewState, ImportReviewState.pending);
    expect(batch.rows.single.isExcluded, isFalse);
    expect(excluded.rows.single.reviewState, ImportReviewState.excluded);
    expect(excluded.rows.single.isExcluded, isTrue);
    expect(
      excluded.toBatchParseResult().transactions.single.isExcluded,
      isTrue,
    );
  });
}

ImportFileSource _source() {
  return const ImportFileSource(
    type: ImportSourceType.otherCsv,
    fileName: '账单.csv',
  );
}

ImportDraftRow _validRow({
  required int lineNumber,
  TransactionType type = TransactionType.expense,
  String categoryCode = 'groceries_food',
  String? merchant = '菜市场',
  List<ImportIssue> issues = const [],
  ImportDuplicateNotice? duplicateNotice,
}) {
  return ImportDraftRow(
    rawRow: ImportRawRow(
      lineNumber: lineNumber,
      rawText: '2026-08-31,$lineNumber,35.00',
    ),
    transactionDate: '2026-08-31',
    amountCents: 3500,
    transactionType: type,
    merchant: merchant,
    categorySuggestions: [ImportCategorySuggestion(categoryCode: categoryCode)],
    issues: issues,
    duplicateNotice: duplicateNotice,
  );
}

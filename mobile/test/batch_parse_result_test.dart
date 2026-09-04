import 'package:flutter_test/flutter_test.dart';
import 'package:smartledger/domain/parser/batch_parse_result.dart';
import 'package:smartledger/domain/parser/parse_result.dart';
import 'package:smartledger/domain/parser/transaction_parser.dart';
import 'package:smartledger/shared/clock.dart';

void main() {
  final parser = TransactionParser(clock: FixedClock(DateTime(2026, 8, 30, 9)));

  test('有效候选可以转换为 NewLedgerTransaction', () {
    final candidate = _candidate(1, '买菜35', parser.parse('买菜35'));

    expect(candidate.hasDraft, isTrue);
    expect(candidate.hasBlockingIssues, isFalse);
    expect(candidate.canConvertToTransaction, isTrue);
    expect(candidate.toNewLedgerTransaction(), isNotNull);
    expect(candidate.toNewLedgerTransaction()!.amountCents, 3500);
    expect(candidate.toNewLedgerTransaction()!.category, 'groceries_food');
  });

  test('待确认候选在明确确认前不能提交', () {
    final candidate = _candidate(1, '35买菜', parser.parse('35买菜'));
    final batch = BatchParseResult(
      originalText: '35买菜',
      transactions: [candidate],
    );

    expect(candidate.requiresConfirmation, isTrue);
    expect(candidate.hasBlockingIssues, isFalse);
    expect(candidate.canConvertToTransaction, isTrue);
    expect(candidate.readyForSubmission, isFalse);
    expect(batch.canSubmit, isFalse);
    expect(batch.updateCandidate(candidate.confirm()).canSubmit, isTrue);
  });

  test('阻塞候选不能转换', () {
    final candidate = _candidate(1, '买菜', parser.parse('买菜'));

    expect(candidate.hasDraft, isTrue);
    expect(candidate.hasBlockingIssues, isTrue);
    expect(candidate.canConvertToTransaction, isFalse);
    expect(candidate.toNewLedgerTransaction(), isNull);
  });

  test('空草稿候选不会被静默丢弃', () {
    final candidate = _candidate(1, '你好', parser.parse('你好'));
    final batch = BatchParseResult(
      originalText: '你好',
      transactions: [candidate],
    );

    expect(batch.transactions, hasLength(1));
    expect(batch.transactions.single.isEmpty, isTrue);
    expect(batch.hasBlockingIssues, isTrue);
    expect(batch.canSubmit, isFalse);
  });

  test('候选可以排除和恢复，且批量对象保持不可变', () {
    final first = _candidate(1, '买菜35', parser.parse('买菜35'));
    final second = _candidate(2, '加油300元', parser.parse('加油300元'));
    final batch = BatchParseResult(
      originalText: '买菜35\n加油300',
      transactions: [first, second],
    );

    final excluded = batch.exclude(1);
    expect(batch.retainedTransactions, hasLength(2));
    expect(excluded.retainedTransactions, hasLength(1));
    expect(excluded.excludedTransactions.single.candidateId, 1);
    expect(excluded.canSubmit, isTrue);

    final restored = excluded.restore(1);
    expect(restored.retainedTransactions, hasLength(2));
    expect(restored.excludedTransactions, isEmpty);
  });

  test('整批包含阻塞候选时不能提交，全部合法时可以提交', () {
    final valid = _candidate(1, '买菜35元', parser.parse('买菜35元'));
    final invalid = _candidate(2, '买菜', parser.parse('买菜'));
    final batch = BatchParseResult(
      originalText: '买菜35元\n买菜',
      transactions: [valid, invalid],
    );

    expect(batch.blockingTransactions.map((item) => item.candidateId), [2]);
    expect(batch.canSubmit, isFalse);
    expect(batch.transactionsToSave, isEmpty);

    final corrected = invalid.copyWith(
      parseResult: parser.parse('买菜20元'),
      originalLine: '买菜20元',
    );
    final correctedBatch = batch.updateCandidate(corrected);
    expect(correctedBatch.hasBlockingIssues, isFalse);
    expect(correctedBatch.canSubmit, isTrue);
    expect(correctedBatch.transactionsToSave, hasLength(2));
  });
}

BatchTransaction _candidate(int id, String originalLine, ParseResult result) {
  return BatchTransaction(
    candidateId: id,
    originalLine: originalLine,
    parseResult: result,
  );
}

final class FixedClock implements Clock {
  const FixedClock(this._now);

  final DateTime _now;

  @override
  DateTime now() => _now;
}

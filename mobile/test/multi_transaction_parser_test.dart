import 'package:flutter_test/flutter_test.dart';
import 'package:smartledger/domain/models/transaction_type.dart';
import 'package:smartledger/domain/parser/multi_transaction_parser.dart';
import 'package:smartledger/shared/clock.dart';

void main() {
  final parser = MultiTransactionParser(
    clock: FixedClock(DateTime(2026, 8, 30, 9)),
  );

  test('支持按换行和中文标点拆分多笔账', () {
    final result = parser.parse('白菜10\n牛奶15，饮料8');

    expect(result.transactions, hasLength(3));
    expect(result.transactions[0].originalLine, '白菜10');
    expect(result.transactions[1].originalLine, '牛奶15');
    expect(result.transactions[2].originalLine, '饮料8');
    expect(result.transactions[0].draft!.amountCents, 1000);
    expect(result.transactions[1].draft!.amountCents, 1500);
    expect(result.transactions[2].draft!.category, 'dining');
  });

  test('支持没有分隔符的连续消费文本', () {
    final result = parser.parse('白菜10牛奶15饮料8');

    expect(result.transactions, hasLength(3));
    expect(
      result.transactions.map((transaction) => transaction.draft!.amountCents),
      [1000, 1500, 800],
    );
  });

  test('单笔带日期时不会把日期数字拆成多笔', () {
    final result = parser.parse('2026年8月20日买菜35');

    expect(result.transactions, hasLength(1));
    expect(result.transactions.single.draft!.transactionDate, '2026-08-20');
    expect(result.transactions.single.draft!.amountCents, 3500);
  });

  test('混合有效和无效行都会保留', () {
    final result = parser.parse('买菜10\n\n你好\n加油300');

    expect(result.transactions, hasLength(4));
    expect(result.transactions[1].isEmpty, isTrue);
    expect(result.transactions[2].isEmpty, isTrue);
    expect(result.blockingTransactions, hasLength(2));
    expect(result.canSubmit, isFalse);
  });

  test('多个金额会按金额边界拆开，而不是由单笔 Parser 静默取值', () {
    final result = parser.parse('买菜35又打车20');

    expect(result.transactions, hasLength(2));
    expect(result.transactions[0].draft!.amountCents, 3500);
    expect(result.transactions[1].draft!.amountCents, 2000);
    expect(result.transactions[1].draft!.type, TransactionType.expense);
  });

  test('银行卡尾号和订单号中的数字不会被当成消费金额', () {
    final result = parser.parse('银行卡尾号1234买菜35元');

    expect(result.transactions, hasLength(1));
    expect(result.transactions.single.draft!.amountCents, 3500);
  });

  test('空输入仍保留一个可识别的空候选', () {
    final result = parser.parse('');

    expect(result.transactions, hasLength(1));
    expect(result.transactions.single.isEmpty, isTrue);
    expect(result.canSubmit, isFalse);
  });
}

final class FixedClock implements Clock {
  const FixedClock(this._now);

  final DateTime _now;

  @override
  DateTime now() => _now;
}

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:smartledger/domain/import/import_contract.dart';
import 'package:smartledger/domain/import/alipay_csv_parser.dart';
import 'package:smartledger/domain/models/transaction_type.dart';
import 'package:smartledger/shared/clock.dart';

void main() {
  const parser = AlipayCsvParser();

  test('跳过支付宝表头说明行，解析收支、金额、分类和订单号', () {
    const csv = '''支付宝交易记录明细
账号：example@alipay.com

交易时间,交易分类,收/支,金额,交易对方,商品说明,交易订单号,资金状态
2026-08-31 12:30:00,餐饮,支出,35.00,星巴克,"咖啡,早餐",ORDER-EXPENSE-1,交易成功
2026/08/30 09:00,工资,收入,100.5,张三,八月工资,ORDER-INCOME-1,交易成功
''';

    final batch = parser.parse(
      csv,
      fileName: '支付宝账单.csv',
      filePath: '/tmp/alipay.csv',
      charset: 'UTF-8',
    );

    expect(batch.source.type, ImportSourceType.alipayCsv);
    expect(batch.source.fileName, '支付宝账单.csv');
    expect(batch.source.filePath, '/tmp/alipay.csv');
    expect(batch.source.charset, 'UTF-8');
    expect(batch.rows, hasLength(2));

    final expense = batch.rows[0];
    expect(expense.rawRow.lineNumber, 5);
    expect(expense.rawRow.fields, [
      '2026-08-31 12:30:00',
      '餐饮',
      '支出',
      '35.00',
      '星巴克',
      '咖啡,早餐',
      'ORDER-EXPENSE-1',
      '交易成功',
    ]);
    expect(expense.transactionDate, '2026-08-31');
    expect(expense.rawAmount, '35.00');
    expect(expense.amountCents, 3500);
    expect(expense.transactionType, TransactionType.expense);
    expect(expense.merchant, '星巴克');
    expect(expense.suggestedCategoryCode, 'dining');
    expect(expense.note, contains('咖啡,早餐'));
    expect(expense.note, contains('ORDER-EXPENSE-1'));
    expect(
      expense.toNewLedgerTransaction()!.originalText,
      expense.rawRow.rawText,
    );

    final income = batch.rows[1];
    expect(income.rawRow.lineNumber, 6);
    expect(income.amountCents, 10050);
    expect(income.transactionType, TransactionType.income);
    expect(income.suggestedCategoryCode, 'salary');
    expect(income.note, contains('ORDER-INCOME-1'));
    expect(income.toNewLedgerTransaction()!.type, TransactionType.income);
  });

  test('退款、关闭、失败和不计入账单状态保留为明确不可入账行', () {
    const csv = '''交易时间,交易分类,收/支,金额,交易对方,商品说明,交易订单号,资金状态
2026-08-31 10:00,购物,支出,20.00,商户,退款商品,REFUND-1,退款成功
2026-08-31 10:01,购物,支出,21.00,商户,关闭商品,CLOSED-1,交易关闭
2026-08-31 10:02,购物,支出,22.00,商户,失败商品,FAILED-1,交易失败
2026-08-31 10:03,转账,收入,23.00,商户,不入账转账,NOBOOK-1,不计入账单
''';

    final rows = parser.parse(csv).rows;

    expect(rows, hasLength(4));
    expect(rows[0].status, ImportRowStatus.refund);
    expect(rows[0].amountCents, 2000);
    expect(rows[0].toNewLedgerTransaction(), isNull);
    expect(
      rows[0].issues.any((issue) => issue.code == ImportIssueCodes.refundRow),
      isTrue,
    );

    for (final row in rows.skip(1)) {
      expect(row.status, ImportRowStatus.failed);
      expect(row.hasBlockingIssues, isTrue);
      expect(row.toNewLedgerTransaction(), isNull);
      expect(row.rawRow.lineNumber, greaterThan(1));
    }
    expect(
      rows[3].issues.any((issue) => issue.code == 'non_bookable_status'),
      isTrue,
    );
  });

  test('成功行的坏字段保留候选和行号，并带出可读原因', () {
    const csv = '''交易时间,交易分类,收/支,金额,交易对方,商品说明,交易订单号,资金状态
2026-08-31 10:00,购物,支出,12.345,商户,商品,BAD-AMOUNT,交易成功
2026-02-30 10:01,购物,支出,22.00,商户,商品,BAD-DATE,交易成功
2026-08-31 10:02,购物,支出,33.00,商户,商品,GOOD-1,未知资金状态
坏行,只有两列

''';

    final rows = parser.parse(csv).rows;

    expect(rows, hasLength(5));
    expect(rows[0].rawRow.lineNumber, 2);
    expect(rows[0].status, ImportRowStatus.candidate);
    expect(rows[0].amountCents, isNull);
    expect(
      rows[0].issues.any(
        (issue) => issue.code == ImportIssueCodes.invalidAmount,
      ),
      isTrue,
    );

    expect(rows[1].rawRow.lineNumber, 3);
    expect(rows[1].transactionDate, isNull);
    expect(
      rows[1].issues.any((issue) => issue.code == ImportIssueCodes.invalidDate),
      isTrue,
    );

    expect(rows[2].rawRow.lineNumber, 4);
    expect(rows[2].status, ImportRowStatus.unknown);
    expect(
      rows[2].issues.any((issue) => issue.code == 'unsupported_status'),
      isTrue,
    );

    expect(rows[3].rawRow.lineNumber, 5);
    expect(rows[3].status, ImportRowStatus.unknown);
    expect(
      rows[3].issues.any((issue) => issue.message.contains('第 5 行')),
      isTrue,
    );
    expect(rows[4].rawRow.lineNumber, 6);
    expect(rows[4].status, ImportRowStatus.empty);
  });

  test('支持带引号的逗号、BOM和可选扩展列', () {
    const csv =
        '\uFEFF交易时间,交易分类,收/支,金额,交易对方,商品说明,交易订单号,商家订单号,资金状态\r\n'
        '2026-08-31 10:00,交通,支出,"1,234.56",滴滴,"机场,快车",ORDER-2,MERCHANT-2,交易成功\r\n';

    final row = parser.parse(csv).rows.single;

    expect(row.rawRow.lineNumber, 2);
    expect(row.amountCents, 123456);
    expect(row.transactionType, TransactionType.expense);
    expect(row.suggestedCategoryCode, 'transportation');
    expect(row.note, contains('机场,快车'));
    expect(row.note, contains('ORDER-2'));
  });

  test('UTF-8 字节入口支持引号内换行并保留原始行追溯', () {
    const csv =
        '\uFEFF商品说明,资金状态,交易对方,金额（元）,收/支,交易时间,交易分类,交易订单号\n'
        '"第一行\n第二行",交易成功,连锁店,12.34,支出,2026-09-01 08:00,餐饮,ALIPAY-MULTI\n';

    final row = parser.parseBytes(utf8.encode(csv)).rows.single;

    expect(row.rawRow.lineNumber, 2);
    expect(row.rawRow.fields.first, '第一行\n第二行');
    expect(row.rawRow.rawText, contains('第一行\n第二行'));
    expect(row.amountCents, 1234);
    expect(row.transactionType, TransactionType.expense);
    expect(row.suggestedCategoryCode, 'dining');
    expect(row.note, contains('第一行\n第二行'));
  });

  test('新增固定分类从支付宝分类和商品字段生成匹配建议', () {
    const csv = '''交易时间,交易分类,收/支,金额,交易对方,商品说明,交易订单号,资金状态
2026-08-31,服饰美容,支出,120.00,服装店,买衣服,CLOTH-1,交易成功
2026-08-31,教育学习,支出,500.00,培训机构,培训费,EDU-1,交易成功
2026-08-31,保险,支出,800.00,保险公司,保费,INS-1,交易成功
2026-08-31,旅行度假,支出,200.00,酒店,酒店住宿,TRAVEL-1,交易成功
2026-08-31,奖金/绩效,收入,500.00,公司,绩效奖金,BONUS-1,交易成功
2026-08-31,红包/礼金,收入,260.00,亲友,礼金到账,GIFT-1,交易成功
''';

    final rows = parser.parse(csv).rows;

    expect(rows.map((row) => row.suggestedCategoryCode), [
      'clothing_beauty',
      'education_learning',
      'insurance',
      'travel_vacation',
      'bonus',
      'gift_red_envelope',
    ]);
    expect(
      rows
          .take(4)
          .every((row) => row.transactionType == TransactionType.expense),
      isTrue,
    );
    expect(
      rows
          .skip(4)
          .every((row) => row.transactionType == TransactionType.income),
      isTrue,
    );
  });

  test('UTF-8 字节损坏时拒绝静默替换', () {
    expect(
      () => parser.parseBytes([0xE4, 0xB8]),
      throwsA(isA<FormatException>()),
    );
  });

  test('未来日期和超长导入内容在解析阶段生成阻塞问题', () {
    final parser = AlipayCsvParser(
      clock: _FixedClock(DateTime(2026, 9, 2, 10)),
    );
    final longProduct = List<String>.filled(510, '长').join();
    final batch = parser.parse(
      '交易时间,交易分类,收/支,金额,交易对方,商品说明,交易订单号,资金状态\n'
      '2026-09-03,餐饮,支出,10.00,商户,$longProduct,ORDER-LONG,交易成功\n',
    );

    final row = batch.rows.single;
    expect(row.hasBlockingIssues, isTrue);
    expect(
      row.issues.any((issue) => issue.code == ImportIssueCodes.futureDate),
      isTrue,
    );
    expect(
      row.issues.any((issue) => issue.code == ImportIssueCodes.rawTextTooLong),
      isTrue,
    );
    expect(
      row.issues.any((issue) => issue.code == ImportIssueCodes.noteTooLong),
      isTrue,
    );
    expect(row.toNewLedgerTransaction(), isNull);
  });
}

final class _FixedClock implements Clock {
  const _FixedClock(this._now);

  final DateTime _now;

  @override
  DateTime now() => _now;
}

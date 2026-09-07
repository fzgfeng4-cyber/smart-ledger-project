import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:smartledger/domain/import/import_contract.dart';
import 'package:smartledger/domain/import/wechat_csv_parser.dart';
import 'package:smartledger/domain/models/transaction_type.dart';
import 'package:smartledger/shared/clock.dart';

void main() {
  const parser = WechatCsvParser();

  test('支持 UTF-8 BOM、说明行、重排列序和带引号逗号', () {
    final csv =
        '\uFEFF微信支付账单明细\n'
        '导出时间：2026-09-01 10:00:00\n'
        '金额(元),商品,交易时间,当前状态,交易单号,收/支,交易对方,交易类型,备注\n'
        '35.50,"午餐,大杯",2026-08-31 12:34:56,支付成功,wx-001,支出,麦当劳,商户消费,\n'
        '\n';

    final batch = parser.parse(csv, fileName: 'wechat.csv');

    expect(batch.source.type, ImportSourceType.wechatCsv);
    expect(batch.source.fileName, 'wechat.csv');
    expect(batch.rows, hasLength(5));
    expect(batch.unknownRows, hasLength(3));
    expect(batch.emptyRows, hasLength(1));
    expect(batch.candidateRows, hasLength(1));

    final row = batch.candidateRows.single;
    expect(row.rawRow.lineNumber, 4);
    expect(row.rawRow.fields[1], '午餐,大杯');
    expect(row.rawDate, '2026-08-31 12:34:56');
    expect(row.transactionDate, '2026-08-31');
    expect(row.rawAmount, '35.50');
    expect(row.amountCents, 3550);
    expect(row.transactionType, TransactionType.expense);
    expect(row.merchant, '麦当劳');
    expect(row.note, contains('午餐,大杯'));
    expect(row.note, contains('交易单号：wx-001'));
    expect(row.suggestedCategoryCode, 'dining');
  });

  test('UTF-8 字节入口支持 BOM，金额精确转换为整数分', () {
    final csv =
        '\uFEFF交易时间,收支,交易对方,金额（元）,当前状态\n'
        '2026/08/31 08:00:00,收入,工资到账,0.01,交易成功\n';

    final batch = parser.parseBytes(utf8.encode(csv), fileName: '收入.csv');
    final row = batch.candidateRows.single;

    expect(batch.source.charset, 'UTF-8');
    expect(row.amountCents, 1);
    expect(row.transactionDate, '2026-08-31');
    expect(row.transactionType, TransactionType.income);
    expect(row.suggestedCategoryCode, 'salary');
  });

  test('新增固定分类从微信商品和交易类型字段生成匹配建议', () {
    const csv = '''交易时间,收支,交易对方,金额(元),商品,当前状态,交易单号
2026-08-31,支出,服装店,120.00,买衣服,交易成功,CLOTH-1
2026-08-31,支出,培训机构,500.00,培训费,交易成功,EDU-1
2026-08-31,支出,保险公司,800.00,保费,交易成功,INS-1
2026-08-31,支出,酒店,200.00,酒店住宿,交易成功,TRAVEL-1
2026-08-31,收入,公司,500.00,绩效奖金,交易成功,BONUS-1
2026-08-31,收入,亲友,260.00,礼金到账,交易成功,GIFT-1
''';

    final rows = parser.parse(csv).candidateRows;

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

  test('收入、退款和失败状态不会默认为普通支出', () {
    final csv =
        '交易时间,交易类型,收/支,金额(元),交易对方,商品,当前状态,交易单号\n'
        '2026-08-31,工资到账,收入,5000,公司,八月工资,交易成功,income-1\n'
        '2026-08-30,退款,,20,商户,订单退款,退款成功,refund-1\n'
        '2026-08-29,商户消费,支出,12.50,便利店,日用品,交易失败,failed-1\n';

    final batch = parser.parse(csv);

    expect(batch.candidateRows, hasLength(1));
    expect(batch.candidateRows.single.transactionType, TransactionType.income);
    expect(batch.candidateRows.single.suggestedCategoryCode, 'salary');
    expect(batch.refundRows, hasLength(1));
    expect(batch.refundRows.single.transactionType, isNull);
    expect(batch.refundRows.single.rawRow.lineNumber, 3);
    expect(batch.refundRows.single.issues, contains(isA<ImportIssue>()));
    expect(
      batch.refundRows.single.issues.any(
        (issue) => issue.code == ImportIssueCodes.refundRow,
      ),
      isTrue,
    );
    expect(batch.failedRows, hasLength(1));
    expect(
      batch.failedRows.single.issues.any(
        (issue) => issue.code == ImportIssueCodes.failedRow,
      ),
      isTrue,
    );
    expect(batch.failedRows.single.toNewLedgerTransaction(), isNull);
  });

  test('坏行保留行号、原始文本和明确问题，不静默丢失', () {
    final csv =
        '交易时间,收支,交易对方,金额(元),当前状态\n'
        '2026-08-31,支出,菜市场,12.345,交易成功\n'
        '2026-08-30,,未知商户,8,交易成功\n'
        '2026-08-29,支出,"未闭合,9.00,交易成功\n';

    final batch = parser.parse(csv);

    expect(batch.rows, hasLength(4));
    expect(batch.rows.map((row) => row.rawRow.lineNumber), [1, 2, 3, 4]);
    expect(batch.rows[2].rawRow.rawText, contains('未知商户'));
    expect(
      batch.rows[1].issues.any(
        (issue) => issue.code == ImportIssueCodes.invalidAmount,
      ),
      isTrue,
    );
    expect(
      batch.rows[2].issues.any(
        (issue) => issue.code == ImportIssueCodes.unknownDirection,
      ),
      isTrue,
    );
    expect(batch.rows[3].status, ImportRowStatus.unknown);
    expect(batch.rows[3].rawRow.rawText, contains('未闭合'));
    expect(batch.rows[3].issues.single.message, contains('引号'));
  });

  test('没有微信表头时不猜固定列序，而是保留每一行并说明原因', () {
    final batch = parser.parse('2026-08-31,支出,菜市场,10.00\n');

    expect(batch.rows, hasLength(1));
    expect(batch.rows.single.status, ImportRowStatus.unknown);
    expect(batch.rows.single.rawRow.rawText, '2026-08-31,支出,菜市场,10.00');
    expect(batch.rows.single.issues.single.message, contains('固定列序'));
    expect(batch.candidateRows, isEmpty);
  });

  test('未来日期和超长导入内容在解析阶段生成阻塞问题', () {
    final parser = WechatCsvParser(
      clock: _FixedClock(DateTime(2026, 9, 2, 10)),
    );
    final longProduct = List<String>.filled(510, '长').join();
    final batch = parser.parse(
      '交易时间,收支,交易对方,金额(元),商品,当前状态\n'
      '2026-09-03,支出,商户,10.00,$longProduct,交易成功\n',
    );

    final row = batch.candidateRows.single;
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

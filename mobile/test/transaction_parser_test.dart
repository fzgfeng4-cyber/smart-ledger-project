import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:smartledger/domain/models/transaction_type.dart';
import 'package:smartledger/domain/parser/parse_result.dart';
import 'package:smartledger/domain/parser/transaction_parser.dart';
import 'package:smartledger/shared/clock.dart';

void main() {
  final parser = TransactionParser(clock: FixedClock(DateTime(2026, 8, 30, 9)));

  test('parses documented normal examples into draft fields', () {
    final examples = <_ExpectedDraft>[
      _ExpectedDraft(
        '5块买菜',
        500,
        TransactionType.expense,
        'groceries_food',
        '买菜',
        '2026-08-30',
      ),
      _ExpectedDraft(
        '18块吃面',
        1800,
        TransactionType.expense,
        'dining',
        '吃面',
        '2026-08-30',
      ),
      _ExpectedDraft(
        '300加油',
        30000,
        TransactionType.expense,
        'vehicle_fuel',
        '加油',
        '2026-08-30',
      ),
      _ExpectedDraft(
        '20打车',
        2000,
        TransactionType.expense,
        'transportation',
        '打车',
        '2026-08-30',
      ),
      _ExpectedDraft(
        '8000工资',
        800000,
        TransactionType.income,
        'salary',
        '工资',
        '2026-08-30',
      ),
      _ExpectedDraft(
        '工资到账8000',
        800000,
        TransactionType.income,
        'salary',
        '工资',
        '2026-08-30',
      ),
      _ExpectedDraft(
        '昨天买菜35',
        3500,
        TransactionType.expense,
        'groceries_food',
        '买菜',
        '2026-08-29',
      ),
      _ExpectedDraft(
        '今天午饭15块',
        1500,
        TransactionType.expense,
        'dining',
        '午饭',
        '2026-08-30',
      ),
      _ExpectedDraft(
        '给孩子买东西80',
        8000,
        TransactionType.expense,
        'children',
        '给孩子买东西',
        '2026-08-30',
      ),
      _ExpectedDraft(
        '带孩子吃饭86',
        8600,
        TransactionType.expense,
        'dining',
        '带孩子吃饭',
        '2026-08-30',
      ),
      _ExpectedDraft(
        '奖金500',
        50000,
        TransactionType.income,
        'bonus',
        '奖金',
        '2026-08-30',
      ),
      _ExpectedDraft(
        '话费50',
        5000,
        TransactionType.expense,
        'communication',
        '话费',
        '2026-08-30',
      ),
      _ExpectedDraft(
        '医院挂号20',
        2000,
        TransactionType.expense,
        'medical',
        '医院挂号',
        '2026-08-30',
      ),
      _ExpectedDraft(
        '房租800',
        80000,
        TransactionType.expense,
        'housing',
        '房租',
        '2026-08-30',
      ),
      _ExpectedDraft(
        '买衣服200',
        20000,
        TransactionType.expense,
        'clothing_beauty',
        '买衣服',
        '2026-08-30',
      ),
      _ExpectedDraft(
        '水果28',
        2800,
        TransactionType.expense,
        'groceries_food',
        '水果',
        '2026-08-30',
      ),
      _ExpectedDraft(
        '麦当劳35',
        3500,
        TransactionType.expense,
        'dining',
        '麦当劳',
        '2026-08-30',
      ),
    ];

    for (final example in examples) {
      final result = parser.parse(example.text);
      final draft = result.draft;

      expect(draft, isNotNull, reason: example.text);
      expect(draft!.amountCents, example.amountCents, reason: example.text);
      expect(draft.type, example.type, reason: example.text);
      expect(draft.category, example.category, reason: example.text);
      expect(draft.note, example.note, reason: example.text);
      expect(draft.originalText, example.text, reason: example.text);
      expect(
        draft.transactionDate,
        example.transactionDate,
        reason: example.text,
      );
    }
  });

  test('ready status still requires user confirmation before saving', () {
    final result = parser.parse('35块买菜');

    expect(result.status, ParseStatus.ready);
    expect(result.needsConfirmation, isFalse);
    expect(result.requiresConfirmation, isTrue);
    expect(result.draft!.toMap(), {
      'amount_cents': 3500,
      'type': 'expense',
      'category': 'groceries_food',
      'note': '买菜',
      'original_text': '35块买菜',
      'transaction_date': '2026-08-30',
    });
  });

  test('only amount does not guess type or category', () {
    final result = parser.parse('35');

    expect(result.status, ParseStatus.needsInput);
    expect(result.draft!.amountCents, 3500);
    expect(result.draft!.type, isNull);
    expect(result.draft!.category, isNull);
    expect(result.missingFields, containsAll(['type', 'category']));
    expect(result.hasIssue('TYPE_UNKNOWN'), isTrue);
    expect(result.hasIssue('BARE_AMOUNT'), isTrue);
  });

  test('missing amount keeps known type and category but blocks saving', () {
    final result = parser.parse('买菜');

    expect(result.status, ParseStatus.needsInput);
    expect(result.draft!.amountCents, isNull);
    expect(result.draft!.type, TransactionType.expense);
    expect(result.draft!.category, 'groceries_food');
    expect(result.draft!.note, '买菜');
    expect(result.isMissingAmount, isTrue);
    expect(result.missingFields, contains('amount_cents'));
  });

  test('multiple amounts are not auto selected or split', () {
    final result = parser.parse('买菜35又打车20');

    expect(result.status, ParseStatus.needsInput);
    expect(result.draft!.amountCents, isNull);
    expect(result.draft!.type, TransactionType.expense);
    expect(result.draft!.category, isNull);
    expect(result.draft!.note, '买菜又打车');
    expect(result.hasMultipleAmounts, isTrue);
    expect(result.hasIssue('CATEGORY_AMBIGUOUS'), isTrue);
    expect(result.missingFields, containsAll(['amount_cents', 'category']));
  });

  test('decimal amounts are converted to cents without double precision', () {
    expect(parser.parse('35.8元吃饭').draft!.amountCents, 3580);
    expect(parser.parse('35.80元吃饭').draft!.amountCents, 3580);
    expect(parser.parse('0.01元买菜').draft!.amountCents, 1);
  });

  test('zero negative and over precise amounts are invalid', () {
    final inputs = ['0元买菜', '-5元买菜', '35.123元吃饭'];

    for (final input in inputs) {
      final result = parser.parse(input);
      expect(result.status, ParseStatus.needsInput, reason: input);
      expect(result.draft!.amountCents, isNull, reason: input);
      expect(result.hasIssue('INVALID_AMOUNT'), isTrue, reason: input);
    }
  });

  test('amount beyond sqlite integer range is invalid', () {
    final result = parser.parse('999999999999999999999999999999元工资');

    expect(result.status, ParseStatus.needsInput);
    expect(result.draft!.amountCents, isNull);
    expect(result.hasIssue('INVALID_AMOUNT'), isTrue);
  });

  test('empty and meaningless text do not create a draft', () {
    for (final input in ['', '   ', '你好']) {
      final result = parser.parse(input);
      expect(result.status, ParseStatus.noDraft, reason: input);
      expect(result.draft, isNull, reason: input);
      expect(result.needsConfirmation, isFalse, reason: input);
      expect(result.requiresConfirmation, isFalse, reason: input);
      expect(result.issues, isEmpty, reason: input);
    }
  });

  test('income keywords use income type and fixed income category codes', () {
    final cases = {
      '分红500': 'investment_income',
      '奖金500': 'bonus',
      '收款100': 'other_income',
      '薪资9000': 'salary',
      '收入100': 'other_income',
    };

    for (final entry in cases.entries) {
      final result = parser.parse(entry.key);
      expect(result.draft!.type, TransactionType.income, reason: entry.key);
      expect(result.draft!.category, entry.value, reason: entry.key);
    }
  });

  test('expense keyword categories migrate fixed code rules', () {
    final cases = {
      '纸巾30': 'daily_necessities',
      '地铁4': 'transportation',
      '电影票60': 'entertainment',
      '买药25': 'medical',
      '宽带100': 'communication',
      '停车12': 'vehicle_fuel',
    };

    for (final entry in cases.entries) {
      final result = parser.parse(entry.key);
      expect(result.draft!.type, TransactionType.expense, reason: entry.key);
      expect(result.draft!.category, entry.value, reason: entry.key);
    }
  });

  test('新增固定支出和收入分类可由一句话稳定解析', () {
    final cases = {
      '买衣服200': ('clothing_beauty', TransactionType.expense),
      '培训费800': ('education_learning', TransactionType.expense),
      '酒店住宿500': ('travel_vacation', TransactionType.expense),
      '随礼200': ('gifts_social', TransactionType.expense),
      '猫砂60': ('pets', TransactionType.expense),
      '买手机2000': ('digital_appliances', TransactionType.expense),
      '瑜伽300': ('fitness_sports', TransactionType.expense),
      '分期还款1000': ('debt_repayment', TransactionType.expense),
      '交个税50': ('taxes_fees', TransactionType.expense),
      '募捐100': ('charity_donation', TransactionType.expense),
      '绩效奖金5000': ('bonus', TransactionType.income),
      '劳务费600': ('freelance', TransactionType.income),
      '经营收入3000': ('business_income', TransactionType.income),
      '股息收入50': ('investment_income', TransactionType.income),
      '租赁收入2000': ('rental_income', TransactionType.income),
      '津贴500': ('benefits_subsidies', TransactionType.income),
      '退休工资3000': ('pension', TransactionType.income),
      '收到礼金200': ('gift_red_envelope', TransactionType.income),
    };

    for (final entry in cases.entries) {
      final result = parser.parse(entry.key);
      expect(result.draft!.category, entry.value.$1, reason: entry.key);
      expect(result.draft!.type, entry.value.$2, reason: entry.key);
    }
  });

  test('服饰关键词使用服饰美容固定分类', () {
    final result = parser.parse('买衣服200');

    expect(result.draft!.category, 'clothing_beauty');
    expect(result.draft!.type, TransactionType.expense);
  });

  test('core consumption behavior wins over child scene keyword', () {
    final result = parser.parse('带孩子吃饭86');

    expect(result.status, ParseStatus.needsConfirmation);
    expect(result.draft!.category, 'dining');
    expect(result.hasIssue('CATEGORY_CONFLICT'), isTrue);
    expect(
      result.issues
          .singleWhere((issue) => issue.code == 'CATEGORY_CONFLICT')
          .candidates,
      ['dining', 'children'],
    );
  });

  test('child beneficiary can be category when no concrete item exists', () {
    final result = parser.parse('给孩子买东西80');

    expect(result.draft!.type, TransactionType.expense);
    expect(result.draft!.category, 'children');
    expect(result.hasIssue('CATEGORY_CONFLICT'), isFalse);
  });

  test('date parsing supports V1 simple expressions', () {
    final cases = {
      '前天买菜35': '2026-08-28',
      '8月20日买菜35': '2026-08-20',
      '2026年8月20日买菜35': '2026-08-20',
      '2026-08-20买菜35': '2026-08-20',
    };

    for (final entry in cases.entries) {
      final result = parser.parse(entry.key);
      expect(result.draft!.transactionDate, entry.value, reason: entry.key);
    }
  });

  test('future dates are parsed but block saving', () {
    final result = parser.parse('12月20日买菜35');

    expect(result.status, ParseStatus.needsInput);
    expect(result.draft!.transactionDate, '2026-12-20');
    expect(result.hasFutureDate, isTrue);
    expect(result.missingFields, isNot(contains('transaction_date')));
  });

  test(
    'invalid and unsupported dates block saving without defaulting to today',
    () {
      final invalid = parser.parse('2月30日买菜35');
      final unsupported = parser.parse('上周三买菜35');

      expect(invalid.status, ParseStatus.needsInput);
      expect(invalid.draft!.transactionDate, isNull);
      expect(invalid.hasIssue('INVALID_DATE'), isTrue);
      expect(unsupported.status, ParseStatus.needsInput);
      expect(unsupported.draft!.transactionDate, isNull);
      expect(unsupported.hasIssue('UNSUPPORTED_DATE'), isTrue);
    },
  );

  test('income and expense conflict keeps type undecided', () {
    final result = parser.parse('工资到账后交房租8000');

    expect(result.status, ParseStatus.needsInput);
    expect(result.draft!.type, isNull);
    expect(result.draft!.category, isNull);
    expect(result.hasIssue('TYPE_CONFLICT'), isTrue);
  });

  test('具体收入长词优先于工资短词', () {
    final result = parser.parse('退休工资3000');

    expect(result.draft!.type, TransactionType.income);
    expect(result.draft!.category, 'pension');
  });

  test('多个具体收入分类触发确认而不静默选择工资', () {
    final result = parser.parse('工资和奖金8000');

    expect(result.status, ParseStatus.needsConfirmation);
    expect(result.draft!.type, TransactionType.income);
    expect(result.draft!.category, 'other_income');
    expect(result.hasIssue('CATEGORY_AMBIGUOUS'), isTrue);
  });

  test('贷款或借款到账不回退为收入', () {
    for (final text in ['贷款到账10000', '借款到账5000']) {
      final result = parser.parse(text);

      expect(result.draft!.type, isNull, reason: text);
      expect(result.draft!.category, isNull, reason: text);
      expect(result.hasIssue('TYPE_UNKNOWN'), isTrue, reason: text);
    }
  });

  test('退款不可直接记为支出或收入', () {
    final result = parser.parse('退款买衣服200');

    expect(result.draft!.type, isNull);
    expect(result.draft!.category, isNull);
    expect(result.hasIssue('TYPE_UNKNOWN'), isTrue);
  });

  test('original text is preserved exactly while note uses parse copy', () {
    const original = '  今天午饭15块  ';
    final result = parser.parse(original);

    expect(result.originalText, original);
    expect(result.draft!.originalText, original);
    expect(result.draft!.note, '午饭');
  });

  test('parser module stays pure and does not import sqlite', () {
    final parserSources = [
      File('lib/domain/parser/parse_result.dart'),
      File('lib/domain/parser/classification_service.dart'),
      File('lib/domain/parser/transaction_parser.dart'),
    ].map((file) => file.readAsStringSync()).join('\n');

    expect(parserSources, isNot(contains('sqflite')));
    expect(parserSources, isNot(contains('TransactionRepository')));
    expect(parserSources, isNot(contains('Database')));
  });
}

final class _ExpectedDraft {
  const _ExpectedDraft(
    this.text,
    this.amountCents,
    this.type,
    this.category,
    this.note,
    this.transactionDate,
  );

  final String text;
  final int amountCents;
  final TransactionType type;
  final String category;
  final String note;
  final String transactionDate;
}

final class FixedClock implements Clock {
  const FixedClock(this._now);

  final DateTime _now;

  @override
  DateTime now() => _now;
}

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:smartledger/domain/classification/local_classification_service.dart';
import 'package:smartledger/domain/classification/local_classification_suggestion.dart';
import 'package:smartledger/domain/models/transaction_type.dart';

void main() {
  const service = LocalClassificationService();

  test('蜜雪冰城金额建议餐饮并保留待确认状态', () {
    final result = service.suggest('蜜雪冰城 12');

    expect(result.amountCents, 1200);
    expect(result.type, TransactionType.expense);
    expect(result.categoryCode, 'dining');
    expect(result.categoryLabel, '餐饮');
    expect(
      result.status,
      LocalClassificationSuggestionStatus.needsConfirmation,
    );
    expect(result.needsConfirmation, isTrue);
    expect(result.requiresConfirmation, isTrue);
    expect(result.isFallback, isFalse);
    expect(
      result.ruleHits.any(
        (hit) =>
            hit.ruleId == 'merchant_mixue_bingcheng' &&
            hit.matchedText == '蜜雪冰城',
      ),
      isTrue,
    );
    expect(
      result.ruleHits.any(
        (hit) => hit.field == 'amount' && hit.matchedText == '12',
      ),
      isTrue,
    );
  });

  test('中国石化金额建议车辆加油并输出稳定分类 code', () {
    final result = service.suggest('中国石化 300');

    expect(result.amountCents, 30000);
    expect(result.type, TransactionType.expense);
    expect(result.categoryCode, 'vehicle_fuel');
    expect(result.categoryLabel, '车辆/加油');
    expect(
      result.status,
      LocalClassificationSuggestionStatus.needsConfirmation,
    );
    expect(result.isFallback, isFalse);
    expect(
      result.ruleHits.any(
        (hit) => hit.ruleId == 'merchant_sinopec' && hit.matchedText == '中国石化',
      ),
      isTrue,
    );
  });

  test('未知商户无法稳定分类时回退 other_expense 并提示确认', () {
    final result = service.suggest('便利店 25');

    expect(result.amountCents, 2500);
    expect(result.type, TransactionType.expense);
    expect(result.categoryCode, 'other_expense');
    expect(result.categoryLabel, '其他支出');
    expect(
      result.status,
      LocalClassificationSuggestionStatus.needsConfirmation,
    );
    expect(result.isFallback, isTrue);
    expect(result.message, contains('other_expense'));
    expect(result.message, contains('请确认'));
    expect(
      result.ruleHits.any(
        (hit) => hit.ruleId == 'category_fallback_other_expense',
      ),
      isTrue,
    );
  });

  test('多个分类规则命中时显示冲突而不静默选择分类', () {
    final result = service.suggest('蜜雪冰城加油 12');

    expect(result.amountCents, 1200);
    expect(result.type, TransactionType.expense);
    expect(result.categoryCode, 'other_expense');
    expect(result.isFallback, isTrue);
    expect(
      result.status,
      LocalClassificationSuggestionStatus.needsConfirmation,
    );
    expect(result.message, contains('多个分类'));
    expect(
      result.ruleHits.any((hit) => hit.ruleId == 'category_conflict'),
      isTrue,
    );
  });

  test('日期数字不会被误当成金额或分类依据', () {
    final result = service.suggest('2026-08-20 蜜雪冰城 12');

    expect(result.amountCents, 1200);
    expect(result.categoryCode, 'dining');
    expect(
      result.ruleHits
          .where((hit) => hit.field == 'amount')
          .map((hit) => hit.matchedText),
      ['12'],
    );
  });

  test('只有金额时不猜收支方向并要求补充输入', () {
    final result = service.suggest('12');

    expect(result.amountCents, 1200);
    expect(result.type, isNull);
    expect(result.categoryCode, isNull);
    expect(result.status, LocalClassificationSuggestionStatus.needsInput);
    expect(result.needsConfirmation, isFalse);
    expect(result.isFallback, isFalse);
    expect(result.message, contains('收支方向'));
  });

  test('金额使用整数分且小数不经过 double', () {
    expect(service.suggest('蜜雪冰城 12.50元').amountCents, 1250);
    expect(service.suggest('中国石化 0.01元').amountCents, 1);
  });

  test('本地分类服务识别新增固定支出和收入分类', () {
    final cases = {
      '买衣服 120': ('clothing_beauty', TransactionType.expense),
      '培训费 800': ('education_learning', TransactionType.expense),
      '酒店住宿 500': ('travel_vacation', TransactionType.expense),
      '随礼 200': ('gifts_social', TransactionType.expense),
      '猫砂 60': ('pets', TransactionType.expense),
      '买手机 2000': ('digital_appliances', TransactionType.expense),
      '瑜伽 300': ('fitness_sports', TransactionType.expense),
      '分期还款 1000': ('debt_repayment', TransactionType.expense),
      '交个税 50': ('taxes_fees', TransactionType.expense),
      '募捐 100': ('charity_donation', TransactionType.expense),
      '绩效奖金 5000': ('bonus', TransactionType.income),
      '劳务费 600': ('freelance', TransactionType.income),
      '经营收入 3000': ('business_income', TransactionType.income),
      '股息收入 50': ('investment_income', TransactionType.income),
      '租赁收入 2000': ('rental_income', TransactionType.income),
      '津贴 500': ('benefits_subsidies', TransactionType.income),
      '退休工资 3000': ('pension', TransactionType.income),
      '收到礼金 200': ('gift_red_envelope', TransactionType.income),
    };

    for (final entry in cases.entries) {
      final result = service.suggest(entry.key);
      expect(result.categoryCode, entry.value.$1, reason: entry.key);
      expect(result.type, entry.value.$2, reason: entry.key);
      expect(result.isFallback, isFalse, reason: entry.key);
    }
  });

  test('建议服务不依赖数据库、网络或正式入库对象', () {
    final sourcePaths = [
      'lib/domain/classification/local_classification_service.dart',
      'lib/domain/classification/local_classification_suggestion.dart',
    ];
    final source = sourcePaths
        .map((path) => File(path).readAsStringSync())
        .join('\n');

    expect(source, isNot(contains('sqflite')));
    expect(source, isNot(contains('http')));
    expect(source, isNot(contains('dio')));
    expect(source, isNot(contains('TransactionRepository')));
    expect(source, isNot(contains('Database')));
  });

  test('贷款到账不作为泛化收入建议', () {
    final result = service.suggest('贷款到账 10000');

    expect(result.type, isNull);
    expect(result.categoryCode, isNull);
    expect(result.status, LocalClassificationSuggestionStatus.needsInput);
  });

  test('退款不可回退为默认支出', () {
    final result = service.suggest('退款买衣服 200');

    expect(result.type, isNull);
    expect(result.categoryCode, isNull);
    expect(result.isFallback, isFalse);
    expect(result.message, contains('退款'));
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:smartledger/domain/categories/category_catalog.dart';
import 'package:smartledger/domain/models/transaction_type.dart';

void main() {
  const newExpenses = <String, String>{
    'clothing_beauty': '服饰美容',
    'education_learning': '教育学习',
    'travel_vacation': '旅行度假',
    'gifts_social': '人情往来',
    'pets': '宠物',
    'insurance': '保险',
    'digital_appliances': '数码家电',
    'fitness_sports': '运动健身',
    'debt_repayment': '债务还款',
    'taxes_fees': '税费',
    'charity_donation': '公益捐赠',
  };
  const newIncomes = <String, String>{
    'bonus': '奖金/绩效',
    'freelance': '兼职/劳务',
    'business_income': '经营收入',
    'investment_income': '投资收益',
    'rental_income': '租金收入',
    'benefits_subsidies': '补贴/福利',
    'pension': '养老金',
    'gift_red_envelope': '红包/礼金',
  };

  test('分类目录保留旧 code 并包含完整固定分类', () {
    expect(
      CategoryCatalog.forType(TransactionType.expense)
          .map((category) => category.code)
          .toSet(),
      equals({
        'dining',
        'groceries_food',
        'daily_necessities',
        'transportation',
        'vehicle_fuel',
        'housing',
        'communication',
        'entertainment',
        'children',
        'medical',
        ...newExpenses.keys,
        'other_expense',
      }),
    );
    expect(
      CategoryCatalog.forType(TransactionType.income)
          .map((category) => category.code)
          .toSet(),
      equals({'salary', ...newIncomes.keys, 'other_income'}),
    );

    for (final entry in {...newExpenses, ...newIncomes}.entries) {
      final category = CategoryCatalog.findByCode(entry.key);
      expect(category, isNotNull, reason: entry.key);
      expect(category!.label, entry.value, reason: entry.key);
      expect(
        category.type,
        newExpenses.containsKey(entry.key)
            ? TransactionType.expense
            : TransactionType.income,
        reason: entry.key,
      );
    }

    expect(
      CategoryCatalog.isValidForType(TransactionType.expense, 'salary'),
      isFalse,
    );
    expect(
      CategoryCatalog.isValidForType(TransactionType.income, 'clothing_beauty'),
      isFalse,
    );
  });

  test('新增分类关键词映射到稳定 code 和中文名称', () {
    final cases = {
      '买衣服': ('clothing_beauty', '服饰美容'),
      '培训': ('education_learning', '教育学习'),
      '酒店': ('travel_vacation', '旅行度假'),
      '随礼': ('gifts_social', '人情往来'),
      '猫砂': ('pets', '宠物'),
      '车险': ('insurance', '保险'),
      '笔记本': ('digital_appliances', '数码家电'),
      '瑜伽': ('fitness_sports', '运动健身'),
      '分期还款': ('debt_repayment', '债务还款'),
      '公积金缴费': ('taxes_fees', '税费'),
      '募捐': ('charity_donation', '公益捐赠'),
      '年终奖': ('bonus', '奖金/绩效'),
      '接单收入': ('freelance', '兼职/劳务'),
      '副业收入': ('business_income', '经营收入'),
      '分红': ('investment_income', '投资收益'),
      '租赁收入': ('rental_income', '租金收入'),
      '津贴': ('benefits_subsidies', '补贴/福利'),
      '退休工资': ('pension', '养老金'),
      '收到礼金': ('gift_red_envelope', '红包/礼金'),
    };

    for (final entry in cases.entries) {
      final match = CategoryCatalog.findSearchMatch(entry.key);
      expect(match?.category.code, entry.value.$1, reason: entry.key);
      expect(match?.category.label, entry.value.$2, reason: entry.key);
    }

    expect(CategoryCatalog.findBySearchText('手机费')?.code, 'communication');
    expect(CategoryCatalog.findBySearchText('礼金到账')?.code, 'gift_red_envelope');
  });
}

import '../categories/category_catalog.dart';
import '../models/transaction_type.dart';
import 'parse_result.dart';

final class CategoryKeywordRule {
  const CategoryKeywordRule(this.code, this.keywords);

  final String code;
  final List<String> keywords;
}

final class CategorySelection {
  CategorySelection({required this.code, List<ParseIssue> issues = const []})
    : issues = List.unmodifiable(issues);

  final String? code;
  final List<ParseIssue> issues;
}

final class ClassificationService {
  const ClassificationService();

  List<String> findIncomeKeywords(String text) {
    return _findKeywords(text, _incomeKeywords);
  }

  List<String> findExpenseKeywords(String text) {
    return _findKeywords(text, _expenseKeywords);
  }

  List<String> categoryCandidates(String text) {
    final candidates = <String>[];
    for (final rule in _categoryRules) {
      if (rule.keywords.any(text.contains)) {
        candidates.add(rule.code);
      }
    }

    if (_salaryKeywords.any(text.contains)) {
      candidates.add('salary');
    }
    if (_otherIncomeKeywords.any(text.contains)) {
      candidates.add('other_income');
    }
    return _unique(candidates);
  }

  CategorySelection chooseCategory({
    required TransactionType? type,
    required List<String> candidates,
    required int amountCount,
  }) {
    if (type == null) {
      return CategorySelection(code: null);
    }

    final matching = candidates
        .where((code) => CategoryCatalog.isValidForType(type, code))
        .toList();

    if (type == TransactionType.income) {
      return _chooseIncomeCategory(matching);
    }
    return _chooseExpenseCategory(matching, amountCount);
  }

  static CategorySelection _chooseIncomeCategory(List<String> matching) {
    if (matching.contains('salary')) {
      return CategorySelection(code: 'salary');
    }
    if (matching.length == 1) {
      if (matching.first == 'other_income') {
        return CategorySelection(
          code: 'other_income',
          issues: [
            ParseIssue(
              code: 'CATEGORY_FALLBACK',
              field: 'category',
              message: '收入分类需要确认，请确认是工资还是其他收入。',
              candidates: const ['other_income'],
            ),
          ],
        );
      }
      return CategorySelection(code: matching.first);
    }
    if (matching.length > 1) {
      return CategorySelection(
        code: 'other_income',
        issues: [
          ParseIssue(
            code: 'CATEGORY_AMBIGUOUS',
            field: 'category',
            message: '这句话可能包含多个收入事项，请选择一笔账对应的分类。',
            candidates: matching,
          ),
        ],
      );
    }
    return CategorySelection(
      code: 'other_income',
      issues: [
        ParseIssue(
          code: 'CATEGORY_FALLBACK',
          field: 'category',
          message: '未能确定具体收入分类，请确认其他收入或修改分类。',
          candidates: const ['other_income'],
        ),
      ],
    );
  }

  static CategorySelection _chooseExpenseCategory(
    List<String> matching,
    int amountCount,
  ) {
    if (matching.isEmpty) {
      return CategorySelection(
        code: 'other_expense',
        issues: [
          ParseIssue(
            code: 'CATEGORY_FALLBACK',
            field: 'category',
            message: '未能确定具体分类，请确认其他支出或修改分类。',
            candidates: const ['other_expense'],
          ),
        ],
      );
    }

    if (matching.length == 1) {
      return CategorySelection(code: matching.first);
    }

    if (matching.toSet().containsAll(const {'dining', 'children'}) &&
        matching.length == 2) {
      return CategorySelection(
        code: 'dining',
        issues: [
          ParseIssue(
            code: 'CATEGORY_CONFLICT',
            field: 'category',
            message: '同时出现孩子和餐饮信息，已按核心消费行为建议餐饮，可修改。',
            candidates: const ['dining', 'children'],
          ),
        ],
      );
    }

    if (matching.contains('children')) {
      final coreCategories = matching
          .where((code) => code != 'children')
          .toList();
      if (coreCategories.length == 1) {
        return CategorySelection(
          code: coreCategories.first,
          issues: [
            ParseIssue(
              code: 'CATEGORY_AMBIGUOUS',
              field: 'category',
              message: '同时出现人物和消费事项，已按核心消费行为建议分类，可修改。',
              candidates: matching,
            ),
          ],
        );
      }
    }

    if (amountCount > 1) {
      return CategorySelection(
        code: null,
        issues: [
          ParseIssue(
            code: 'CATEGORY_AMBIGUOUS',
            field: 'category',
            message: '这句话可能包含多个事项，请选择一笔账对应的分类。',
            candidates: matching,
          ),
        ],
      );
    }

    return CategorySelection(
      code: 'other_expense',
      issues: [
        ParseIssue(
          code: 'CATEGORY_AMBIGUOUS',
          field: 'category',
          message: '这句话可能包含多个事项，请选择一笔账对应的分类。',
          candidates: matching,
        ),
      ],
    );
  }

  static List<String> _findKeywords(String text, List<String> keywords) {
    return keywords.where(text.contains).toList();
  }

  static List<String> _unique(List<String> values) {
    final seen = <String>{};
    return [
      for (final value in values)
        if (seen.add(value)) value,
    ];
  }
}

const _categoryRules = <CategoryKeywordRule>[
  CategoryKeywordRule('dining', [
    '麦当劳',
    '餐馆',
    '火锅',
    '早餐',
    '午饭',
    '午餐',
    '晚饭',
    '晚餐',
    '夜宵',
    '吃饭',
    '吃面',
    '外卖',
    '奶茶',
    '咖啡',
    '饮料',
    '吃',
    '饭',
    '面',
    '粉',
    '餐',
  ]),
  CategoryKeywordRule('groceries_food', [
    '菜市场',
    '蔬菜',
    '粮油',
    '食品',
    '水果',
    '零食',
    '生鲜',
    '食材',
    '买菜',
    '买肉',
    '肉',
    '买米',
    '米',
  ]),
  CategoryKeywordRule('daily_necessities', [
    '日用品',
    '纸巾',
    '厕纸',
    '洗衣液',
    '洗发水',
    '牙膏',
    '肥皂',
    '清洁用品',
    '家居消耗品',
  ]),
  CategoryKeywordRule('transportation', [
    '出租车',
    '公交车',
    '打车',
    '公交',
    '地铁',
    '出行',
    '车票',
    '乘车',
    '通勤',
  ]),
  CategoryKeywordRule('vehicle_fuel', [
    '车辆保养',
    '车辆维修',
    '汽车充电',
    '高速费',
    '加油',
    '油费',
    '停车',
    '洗车',
  ]),
  CategoryKeywordRule('housing', [
    '房租',
    '租金',
    '物业',
    '水费',
    '电费',
    '燃气',
    '房贷',
    '居住费用',
  ]),
  CategoryKeywordRule('communication', [
    '手机费',
    '宽带',
    '流量',
    '电话费',
    '通讯费',
    '网络费',
    '话费',
  ]),
  CategoryKeywordRule('entertainment', [
    '演唱会',
    '游戏充值',
    '电影票',
    '电影',
    '游戏',
    '会员',
    '娱乐',
    '唱歌',
    '游玩',
  ]),
  CategoryKeywordRule('children', [
    '儿童用品',
    '孩子学费',
    '奶粉',
    '尿布',
    '给孩子',
    '带孩子',
    '孩子',
    '小孩',
    '宝宝',
    '娃',
  ]),
  CategoryKeywordRule('medical', [
    '医院',
    '看病',
    '挂号',
    '买药',
    '检查',
    '治疗',
    '体检',
    '医疗',
    '药',
  ]),
];

const _incomeKeywords = <String>[
  '工资到账',
  '发工资',
  '兼职收入',
  '红包收入',
  '工资',
  '薪资',
  '月薪',
  '薪酬',
  '奖金',
  '分红',
  '收款',
  '收到',
  '到账',
  '赚到',
  '收入',
];

const _expenseKeywords = <String>[
  '购买',
  '支出',
  '付款',
  '支付',
  '消费',
  '花了',
  '买菜',
  '买东西',
  '买衣服',
  '买',
  '吃饭',
  '吃面',
  '早餐',
  '午饭',
  '午餐',
  '晚饭',
  '晚餐',
  '奶茶',
  '咖啡',
  '买肉',
  '水果',
  '打车',
  '出租车',
  '公交',
  '地铁',
  '加油',
  '停车',
  '房租',
  '话费',
  '看病',
  '挂号',
  '买药',
  '电影',
  '游戏',
];

const _salaryKeywords = <String>['工资到账', '发工资', '工资', '薪资', '月薪', '薪酬'];

const _otherIncomeKeywords = <String>[
  '奖金',
  '分红',
  '兼职收入',
  '收款',
  '收到',
  '赚到',
  '红包收入',
  '收入',
  '到账',
];

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
    if (_isRefundText(text)) {
      return const [];
    }
    final keywords = _findKeywords(text, _incomeKeywords);
    if (!_isLoanDisbursementText(text)) {
      return keywords;
    }
    return keywords
        .where((keyword) => !_genericIncomeKeywords.contains(keyword))
        .toList();
  }

  List<String> findExpenseKeywords(String text) {
    if (_isRefundText(text)) {
      return const [];
    }
    return _findKeywords(text, _expenseKeywords);
  }

  List<String> categoryCandidates(String text) {
    if (_isRefundText(text)) {
      return const [];
    }
    final matches = <_CategoryKeywordMatch>[];
    for (final rule in _categoryRules) {
      for (final keyword in rule.keywords) {
        if (text.contains(keyword)) {
          matches.add(_CategoryKeywordMatch(rule.code, keyword));
        }
      }
    }

    final candidates = <String>[];
    for (final match in matches) {
      final shadowedByMoreSpecificMatch = matches.any(
        (other) =>
            other.code != match.code &&
            match.keyword.length > 1 &&
            other.keyword.length > match.keyword.length &&
            other.keyword.contains(match.keyword),
      );
      if (!shadowedByMoreSpecificMatch) {
        candidates.add(match.code);
      }
    }

    if (_salaryKeywords.any(text.contains) &&
        !_salaryKeywordIsCoveredByLongerIncomeKeyword(text)) {
      candidates.add('salary');
    }
    if (!_isLoanDisbursementText(text) &&
        _otherIncomeKeywords.any(text.contains)) {
      candidates.add('other_income');
    }
    return _unique(candidates);
  }

  bool isRefundText(String text) => _isRefundText(text);

  bool isLoanDisbursementText(String text) => _isLoanDisbursementText(text);

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
    final specific = matching.where((code) => code != 'other_income').toList();
    if (specific.length == 1) {
      return CategorySelection(code: specific.first);
    }
    if (specific.length > 1) {
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

  static bool _salaryKeywordIsCoveredByLongerIncomeKeyword(String text) {
    return _salaryKeywords.any(
      (salaryKeyword) => _categoryRules.any(
        (rule) =>
            CategoryCatalog.isValidForType(TransactionType.income, rule.code) &&
            rule.keywords.any(
              (keyword) =>
                  keyword.length > salaryKeyword.length &&
                  keyword.contains(salaryKeyword) &&
                  text.contains(keyword),
            ),
      ),
    );
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
  CategoryKeywordRule('clothing_beauty', [
    '服饰美容',
    '衣服',
    '服装',
    '鞋子',
    '鞋',
    '化妆品',
    '护肤',
    '美容',
    '理发',
    '美发',
    '美甲',
  ]),
  CategoryKeywordRule('education_learning', [
    '教育学习',
    '教育',
    '学费',
    '培训',
    '课程',
    '学习',
    '书籍',
    '教材',
    '考试',
    '考证',
  ]),
  CategoryKeywordRule('travel_vacation', [
    '旅行度假',
    '旅行',
    '旅游',
    '度假',
    '酒店',
    '民宿',
    '机票',
    '景点',
    '门票',
    '出游',
  ]),
  CategoryKeywordRule('gifts_social', [
    '人情往来',
    '送礼',
    '礼物',
    '礼金',
    '随礼',
    '份子钱',
    '人情',
    '婚礼',
    '白事',
    '发红包',
    '给红包',
  ]),
  CategoryKeywordRule('pets', ['宠物', '猫粮', '狗粮', '猫砂', '宠物医院', '宠物美容']),
  CategoryKeywordRule('insurance', [
    '保险',
    '保费',
    '车险',
    '寿险',
    '意外险',
    '重疾险',
    '商业保险',
  ]),
  CategoryKeywordRule('digital_appliances', [
    '数码家电',
    '手机',
    '电脑',
    '笔记本',
    '平板',
    '耳机',
    '相机',
    '家电',
    '电器',
    '电视',
    '冰箱',
    '洗衣机',
  ]),
  CategoryKeywordRule('fitness_sports', [
    '运动健身',
    '健身',
    '健身房',
    '瑜伽',
    '游泳',
    '球馆',
    '运动',
    '体育',
    '跑步',
  ]),
  CategoryKeywordRule('debt_repayment', [
    '债务还款',
    '还款',
    '信用卡还款',
    '还贷',
    '贷款还款',
    '分期还款',
  ]),
  CategoryKeywordRule('taxes_fees', [
    '税费',
    '税款',
    '个人所得税',
    '个税',
    '社保缴费',
    '公积金缴费',
  ]),
  CategoryKeywordRule('charity_donation', [
    '公益捐赠',
    '捐款',
    '捐赠',
    '公益',
    '慈善',
    '募捐',
  ]),
  CategoryKeywordRule('bonus', ['奖金', '绩效奖金', '年终奖', '提成']),
  CategoryKeywordRule('freelance', ['兼职收入', '兼职', '劳务费', '劳务收入', '接单收入']),
  CategoryKeywordRule('business_income', ['经营收入', '营业收入', '副业收入', '生意收入']),
  CategoryKeywordRule('investment_income', [
    '投资收益',
    '分红',
    '股息',
    '利息收入',
    '理财收益',
  ]),
  CategoryKeywordRule('rental_income', ['租金收入', '收租', '房租收入', '租赁收入']),
  CategoryKeywordRule('benefits_subsidies', ['补贴', '津贴', '福利', '补助']),
  CategoryKeywordRule('pension', ['养老金', '退休金', '退休工资']),
  CategoryKeywordRule('gift_red_envelope', ['红包收入', '收到红包', '礼金到账', '收到礼金']),
];

const _incomeKeywords = <String>[
  '工资到账',
  '发工资',
  '兼职收入',
  '红包收入',
  '收到红包',
  '礼金到账',
  '收到礼金',
  '工资',
  '薪资',
  '月薪',
  '薪酬',
  '奖金',
  '绩效奖金',
  '年终奖',
  '提成',
  '兼职',
  '劳务费',
  '劳务收入',
  '接单收入',
  '经营收入',
  '营业收入',
  '副业收入',
  '生意收入',
  '投资收益',
  '分红',
  '股息',
  '利息收入',
  '理财收益',
  '租金收入',
  '收租',
  '房租收入',
  '租赁收入',
  '补贴',
  '津贴',
  '福利',
  '补助',
  '养老金',
  '退休金',
  '退休工资',
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
  '话费',
  '看病',
  '挂号',
  '买药',
  '电影',
  '游戏',
  '衣服',
  '服装',
  '鞋子',
  '鞋',
  '化妆品',
  '护肤',
  '美容',
  '理发',
  '美发',
  '美甲',
  '教育',
  '学费',
  '培训',
  '课程',
  '学习',
  '书籍',
  '教材',
  '考试',
  '考证',
  '旅行',
  '旅游',
  '度假',
  '酒店',
  '民宿',
  '机票',
  '景点',
  '门票',
  '出游',
  '送礼',
  '礼物',
  '随礼',
  '份子钱',
  '人情',
  '婚礼',
  '白事',
  '发红包',
  '给红包',
  '宠物',
  '猫粮',
  '狗粮',
  '猫砂',
  '宠物医院',
  '宠物美容',
  '保险',
  '保费',
  '车险',
  '寿险',
  '意外险',
  '重疾险',
  '商业保险',
  '手机',
  '电脑',
  '笔记本',
  '平板',
  '耳机',
  '相机',
  '家电',
  '电器',
  '电视',
  '冰箱',
  '洗衣机',
  '健身',
  '健身房',
  '瑜伽',
  '游泳',
  '球馆',
  '运动',
  '体育',
  '跑步',
  '还款',
  '信用卡还款',
  '还贷',
  '贷款还款',
  '分期还款',
  '税费',
  '税款',
  '个人所得税',
  '个税',
  '社保缴费',
  '公积金缴费',
  '捐款',
  '捐赠',
  '公益',
  '慈善',
  '募捐',
];

const _salaryKeywords = <String>['工资到账', '发工资', '工资', '薪资', '月薪', '薪酬'];

const _otherIncomeKeywords = <String>['收款', '收到', '赚到', '收入', '到账'];

const _genericIncomeKeywords = <String>{'收款', '收到', '赚到', '收入', '到账'};

const _refundKeywords = <String>['退款', '退货退款', '退款到账', '退回款', '原路退回', '返还款'];

const _loanDisbursementKeywords = <String>[
  '贷款到账',
  '借款到账',
  '贷款放款',
  '借款入账',
  '借贷到账',
];

bool _isRefundText(String text) => _refundKeywords.any(text.contains);

bool _isLoanDisbursementText(String text) =>
    _loanDisbursementKeywords.any(text.contains);

final class _CategoryKeywordMatch {
  const _CategoryKeywordMatch(this.code, this.keyword);

  final String code;
  final String keyword;
}

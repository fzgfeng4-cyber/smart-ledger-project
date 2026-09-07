import '../models/transaction_type.dart';

final class CategoryDefinition {
  const CategoryDefinition({
    required this.code,
    required this.label,
    required this.type,
  });

  final String code;
  final String label;
  final TransactionType type;
}

final class CategorySearchMatch {
  const CategorySearchMatch({required this.category, required this.keyword});

  final CategoryDefinition category;
  final String keyword;
}

final class CategoryCatalog {
  const CategoryCatalog._();

  static const all = <CategoryDefinition>[
    CategoryDefinition(
      code: 'dining',
      label: '餐饮',
      type: TransactionType.expense,
    ),
    CategoryDefinition(
      code: 'groceries_food',
      label: '买菜/食品',
      type: TransactionType.expense,
    ),
    CategoryDefinition(
      code: 'daily_necessities',
      label: '日用品',
      type: TransactionType.expense,
    ),
    CategoryDefinition(
      code: 'transportation',
      label: '交通',
      type: TransactionType.expense,
    ),
    CategoryDefinition(
      code: 'vehicle_fuel',
      label: '车辆/加油',
      type: TransactionType.expense,
    ),
    CategoryDefinition(
      code: 'housing',
      label: '居住',
      type: TransactionType.expense,
    ),
    CategoryDefinition(
      code: 'communication',
      label: '通讯',
      type: TransactionType.expense,
    ),
    CategoryDefinition(
      code: 'entertainment',
      label: '娱乐',
      type: TransactionType.expense,
    ),
    CategoryDefinition(
      code: 'children',
      label: '孩子',
      type: TransactionType.expense,
    ),
    CategoryDefinition(
      code: 'medical',
      label: '医疗',
      type: TransactionType.expense,
    ),
    CategoryDefinition(
      code: 'clothing_beauty',
      label: '服饰美容',
      type: TransactionType.expense,
    ),
    CategoryDefinition(
      code: 'education_learning',
      label: '教育学习',
      type: TransactionType.expense,
    ),
    CategoryDefinition(
      code: 'insurance',
      label: '保险',
      type: TransactionType.expense,
    ),
    CategoryDefinition(
      code: 'travel_vacation',
      label: '旅行度假',
      type: TransactionType.expense,
    ),
    CategoryDefinition(
      code: 'gifts_social',
      label: '人情往来',
      type: TransactionType.expense,
    ),
    CategoryDefinition(
      code: 'pets',
      label: '宠物',
      type: TransactionType.expense,
    ),
    CategoryDefinition(
      code: 'digital_appliances',
      label: '数码家电',
      type: TransactionType.expense,
    ),
    CategoryDefinition(
      code: 'fitness_sports',
      label: '运动健身',
      type: TransactionType.expense,
    ),
    CategoryDefinition(
      code: 'debt_repayment',
      label: '债务还款',
      type: TransactionType.expense,
    ),
    CategoryDefinition(
      code: 'taxes_fees',
      label: '税费',
      type: TransactionType.expense,
    ),
    CategoryDefinition(
      code: 'charity_donation',
      label: '公益捐赠',
      type: TransactionType.expense,
    ),
    CategoryDefinition(
      code: 'other_expense',
      label: '其他支出',
      type: TransactionType.expense,
    ),
    CategoryDefinition(
      code: 'salary',
      label: '工资',
      type: TransactionType.income,
    ),
    CategoryDefinition(
      code: 'bonus',
      label: '奖金/绩效',
      type: TransactionType.income,
    ),
    CategoryDefinition(
      code: 'freelance',
      label: '兼职/劳务',
      type: TransactionType.income,
    ),
    CategoryDefinition(
      code: 'business_income',
      label: '经营收入',
      type: TransactionType.income,
    ),
    CategoryDefinition(
      code: 'investment_income',
      label: '投资收益',
      type: TransactionType.income,
    ),
    CategoryDefinition(
      code: 'rental_income',
      label: '租金收入',
      type: TransactionType.income,
    ),
    CategoryDefinition(
      code: 'benefits_subsidies',
      label: '补贴/福利',
      type: TransactionType.income,
    ),
    CategoryDefinition(
      code: 'pension',
      label: '养老金',
      type: TransactionType.income,
    ),
    CategoryDefinition(
      code: 'gift_red_envelope',
      label: '红包/礼金',
      type: TransactionType.income,
    ),
    CategoryDefinition(
      code: 'other_income',
      label: '其他收入',
      type: TransactionType.income,
    ),
  ];

  static List<CategoryDefinition> forType(TransactionType type) {
    return all.where((category) => category.type == type).toList();
  }

  static bool isKnownCode(String code) {
    return all.any((category) => category.code == code.trim());
  }

  static bool isValidForType(TransactionType type, String code) {
    return all.any(
      (category) => category.type == type && category.code == code.trim(),
    );
  }

  static CategoryDefinition? findByCode(String code) {
    final normalized = code.trim();
    for (final category in all) {
      if (category.code == normalized) {
        return category;
      }
    }
    return null;
  }

  static CategoryDefinition? findBySearchText(String text) {
    return findSearchMatch(text)?.category;
  }

  static CategorySearchMatch? findSearchMatch(String text) {
    final normalized = text.trim();
    if (normalized.isEmpty) {
      return null;
    }
    CategorySearchMatch? bestMatch;
    for (final category in all) {
      final keywords = _searchKeywords[category.code] ?? const [];
      for (final keyword in keywords) {
        if (normalized.contains(keyword) &&
            (bestMatch == null || keyword.length > bestMatch.keyword.length)) {
          bestMatch = CategorySearchMatch(category: category, keyword: keyword);
        }
      }
    }
    return bestMatch;
  }
}

const _searchKeywords = <String, List<String>>{
  'dining': ['餐饮', '吃饭', '吃面', '午饭', '午餐', '晚饭', '晚餐', '外卖', '奶茶', '咖啡', '饮料'],
  'groceries_food': ['买菜', '食品', '蔬菜', '水果', '买肉', '生鲜', '食材'],
  'daily_necessities': ['日用品', '纸巾', '洗衣液', '洗发水', '牙膏'],
  'transportation': ['交通', '打车', '出租车', '公交', '地铁', '车票'],
  'vehicle_fuel': ['加油', '车辆', '汽油', '油费', '停车', '洗车', '充电'],
  'housing': ['居住', '房租', '物业', '水费', '电费', '燃气', '房贷'],
  'communication': ['通讯', '话费', '手机费', '宽带', '流量', '网络费'],
  'entertainment': ['娱乐', '电影', '游戏', '会员', '唱歌', '游玩'],
  'children': ['孩子', '小孩', '宝宝', '奶粉', '尿布'],
  'medical': ['医疗', '医院', '看病', '挂号', '买药', '药', '体检'],
  'clothing_beauty': [
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
  ],
  'education_learning': [
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
  ],
  'insurance': ['保险', '保费', '车险', '寿险', '意外险', '重疾险', '商业保险'],
  'travel_vacation': [
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
  ],
  'gifts_social': [
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
  ],
  'pets': ['宠物', '猫粮', '狗粮', '猫砂', '宠物医院', '宠物美容'],
  'digital_appliances': [
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
  ],
  'fitness_sports': ['运动健身', '健身', '健身房', '瑜伽', '游泳', '球馆', '运动', '体育', '跑步'],
  'debt_repayment': ['债务还款', '还款', '信用卡还款', '还贷', '贷款还款', '分期还款'],
  'taxes_fees': ['税费', '税款', '个人所得税', '个税', '社保缴费', '公积金缴费'],
  'charity_donation': ['公益捐赠', '捐款', '捐赠', '公益', '慈善', '募捐'],
  'salary': ['工资', '薪资', '月薪', '薪酬'],
  'bonus': ['奖金', '绩效奖金', '年终奖', '提成'],
  'freelance': ['兼职收入', '兼职', '劳务费', '劳务收入', '接单收入'],
  'business_income': ['经营收入', '营业收入', '副业收入', '生意收入'],
  'investment_income': ['投资收益', '分红', '股息', '利息收入', '理财收益'],
  'rental_income': ['租金收入', '收租', '房租收入', '租赁收入'],
  'benefits_subsidies': ['补贴', '津贴', '福利', '补助'],
  'pension': ['养老金', '退休金', '退休工资'],
  'gift_red_envelope': ['红包收入', '收到红包', '礼金到账', '收到礼金'],
  'other_income': ['其他收入', '收入', '收款', '收到', '到账', '赚到'],
};

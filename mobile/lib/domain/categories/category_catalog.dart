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
    for (final category in all) {
      final keywords = _searchKeywords[category.code] ?? const [];
      for (final keyword in keywords) {
        if (normalized.contains(keyword)) {
          return CategorySearchMatch(category: category, keyword: keyword);
        }
      }
    }
    return null;
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
  'salary': ['工资', '薪资', '月薪', '薪酬'],
  'other_income': ['其他收入', '奖金', '分红', '收款', '红包收入'],
};

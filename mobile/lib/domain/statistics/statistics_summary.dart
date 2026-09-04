import '../categories/category_catalog.dart';
import '../models/transaction_type.dart';
import 'statistics_date_range.dart';

final class StatisticsCategoryAmount {
  const StatisticsCategoryAmount({
    required this.categoryCode,
    required this.amountCents,
  });

  final String categoryCode;
  final int amountCents;
}

final class ExpenseCategoryStatistics {
  const ExpenseCategoryStatistics({
    required this.code,
    required this.label,
    required this.amountCents,
    required this.proportion,
  });

  final String code;
  final String label;
  final int amountCents;

  /// 取值范围为 0 到 1；支出总额为 0 时固定为 0.0。
  final double proportion;

  /// 以百分数表示的占比，取值范围为 0 到 100。
  double get percentage => proportion * 100;
}

final class StatisticsSummary {
  const StatisticsSummary({
    required this.range,
    required this.expenseTotalCents,
    required this.incomeTotalCents,
    required this.expenseCategories,
  });

  final StatisticsDateRange range;
  final int expenseTotalCents;
  final int incomeTotalCents;
  final List<ExpenseCategoryStatistics> expenseCategories;

  bool get hasExpenses => expenseTotalCents > 0;

  static StatisticsSummary calculate({
    required StatisticsDateRange range,
    required int expenseTotalCents,
    required int incomeTotalCents,
    required Iterable<StatisticsCategoryAmount> expenseCategories,
  }) {
    final amountsByCode = <String, int>{};
    for (final category in expenseCategories) {
      amountsByCode.update(
        category.categoryCode,
        (amount) => amount + category.amountCents,
        ifAbsent: () => category.amountCents,
      );
    }

    final orderedCodes = amountsByCode.keys.toList()..sort();
    final categories = orderedCodes
        .map((code) {
          final definition = CategoryCatalog.findByCode(code);
          if (definition == null ||
              definition.type != TransactionType.expense) {
            throw StateError('统计数据包含未知支出分类 code: $code');
          }

          final proportion = expenseTotalCents == 0
              ? 0.0
              : amountsByCode[code]! / expenseTotalCents;
          return ExpenseCategoryStatistics(
            code: code,
            label: definition.label,
            amountCents: amountsByCode[code]!,
            proportion: proportion,
          );
        })
        .toList(growable: false);

    return StatisticsSummary(
      range: range,
      expenseTotalCents: expenseTotalCents,
      incomeTotalCents: incomeTotalCents,
      expenseCategories: List.unmodifiable(categories),
    );
  }
}

final class TransactionCategoryAmount {
  const TransactionCategoryAmount({
    required this.categoryCode,
    required this.amountCents,
  });

  final String categoryCode;
  final int amountCents;
}

final class TransactionStatisticsData {
  TransactionStatisticsData({
    required this.expenseTotalCents,
    required this.incomeTotalCents,
    required Iterable<TransactionCategoryAmount> expenseCategories,
  }) : expenseCategories = List.unmodifiable(expenseCategories);

  final int expenseTotalCents;
  final int incomeTotalCents;
  final List<TransactionCategoryAmount> expenseCategories;
}

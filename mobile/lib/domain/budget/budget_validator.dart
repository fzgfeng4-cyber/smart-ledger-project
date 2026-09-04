import '../categories/category_catalog.dart';
import '../models/transaction_type.dart';
import 'budget.dart';

final class BudgetValidationException implements Exception {
  const BudgetValidationException(this.message);

  final String message;

  @override
  String toString() => 'BudgetValidationException: $message';
}

final class BudgetValidator {
  const BudgetValidator._();

  static NewBudget normalizeCreate(NewBudget input) {
    return input.copyWith(
      categoryCode: input.categoryCode.trim(),
      month: input.month.trim(),
    );
  }

  static BudgetUpdate normalizeUpdate(BudgetUpdate input) {
    return BudgetUpdate(
      categoryCode: input.categoryCode?.trim(),
      month: input.month?.trim(),
      amountCents: input.amountCents,
      enabled: input.enabled,
    );
  }

  static void validateCreate(NewBudget input) {
    _validateFields(
      categoryCode: input.categoryCode,
      month: input.month,
      amountCents: input.amountCents,
    );
  }

  static void validateCategoryAndMonth({
    required String categoryCode,
    required String month,
  }) {
    _validateCategory(categoryCode);
    validateMonth(month);
  }

  static void validateMonth(String month) {
    _validateMonth(month);
  }

  static Budget validateUpdateCandidate({
    required Budget existing,
    required BudgetUpdate update,
  }) {
    final candidate = existing.copyWith(
      categoryCode: update.categoryCode,
      month: update.month,
      amountCents: update.amountCents,
      enabled: update.enabled,
    );
    _validateFields(
      categoryCode: candidate.categoryCode,
      month: candidate.month,
      amountCents: candidate.amountCents,
    );
    return candidate;
  }

  static void _validateFields({
    required String categoryCode,
    required String month,
    required int amountCents,
  }) {
    _validateCategory(categoryCode);
    _validateMonth(month);
    if (amountCents <= 0 || amountCents > _maxSqliteInteger) {
      throw const BudgetValidationException('预算金额必须是有效的正整数分');
    }
  }

  static void _validateCategory(String categoryCode) {
    if (!CategoryCatalog.isKnownCode(categoryCode)) {
      throw BudgetValidationException('未知分类 code: $categoryCode');
    }
    if (!CategoryCatalog.isValidForType(
      TransactionType.expense,
      categoryCode,
    )) {
      throw BudgetValidationException('预算分类必须是支出分类: $categoryCode');
    }
  }

  static void _validateMonth(String month) {
    final match = _monthPattern.firstMatch(month);
    if (match == null) {
      throw BudgetValidationException('预算月份必须是有效的 YYYY-MM: $month');
    }

    final year = int.parse(match.group(1)!);
    final monthNumber = int.parse(match.group(2)!);
    if (year == 0 || monthNumber == 0 || monthNumber > 12) {
      throw BudgetValidationException('预算月份必须是有效的 YYYY-MM: $month');
    }
  }

  static final _monthPattern = RegExp(r'^(\d{4})-(\d{2})$');
  static const _maxSqliteInteger = 9223372036854775807;
}

import '../../domain/budget/budget.dart';
import '../../domain/budget/budget_validator.dart';
import '../../shared/clock.dart';
import 'budget_local_data_source.dart';

final class BudgetRepository {
  BudgetRepository(this._dataSource, {Clock? clock})
    : _clock = clock ?? const SystemClock();

  final BudgetLocalDataSource _dataSource;
  final Clock _clock;

  Future<Budget> create(NewBudget input) async {
    final normalized = BudgetValidator.normalizeCreate(input);
    BudgetValidator.validateCreate(normalized);
    final existing = await _dataSource.findByCategoryAndMonth(
      categoryCode: normalized.categoryCode,
      month: normalized.month,
    );
    if (existing != null) {
      throw BudgetValidationException(
        '分类 ${normalized.categoryCode} 在 ${normalized.month} 已有预算',
      );
    }
    return _dataSource.insert(normalized, now: _clock.now());
  }

  Future<Budget?> findById(int id) {
    return _dataSource.findById(id);
  }

  Future<Budget?> findByCategoryAndMonth({
    required String categoryCode,
    required String month,
    bool includeDisabled = true,
  }) {
    final normalizedCategoryCode = categoryCode.trim();
    final normalizedMonth = month.trim();
    BudgetValidator.validateCategoryAndMonth(
      categoryCode: normalizedCategoryCode,
      month: normalizedMonth,
    );
    return _dataSource.findByCategoryAndMonth(
      categoryCode: normalizedCategoryCode,
      month: normalizedMonth,
      includeDisabled: includeDisabled,
    );
  }

  Future<List<Budget>> listForMonth(String month, {bool enabledOnly = true}) {
    final normalizedMonth = month.trim();
    BudgetValidator.validateMonth(normalizedMonth);
    return _dataSource.listForMonth(
      month: normalizedMonth,
      enabledOnly: enabledOnly,
    );
  }

  Future<Budget?> update(int id, BudgetUpdate input) async {
    final existing = await _dataSource.findById(id);
    if (existing == null) {
      return null;
    }

    final normalized = BudgetValidator.normalizeUpdate(input);
    if (!normalized.hasChanges) {
      return existing;
    }

    final candidate = BudgetValidator.validateUpdateCandidate(
      existing: existing,
      update: normalized,
    );
    final identityChanged =
        candidate.categoryCode != existing.categoryCode ||
        candidate.month != existing.month;
    if (identityChanged) {
      final duplicate = await _dataSource.findByCategoryAndMonth(
        categoryCode: candidate.categoryCode,
        month: candidate.month,
      );
      if (duplicate != null && duplicate.id != id) {
        throw BudgetValidationException(
          '分类 ${candidate.categoryCode} 在 ${candidate.month} 已有预算',
        );
      }
    }
    return _dataSource.update(id, normalized, now: _clock.now());
  }

  Future<bool> delete(int id) {
    return _dataSource.delete(id);
  }
}

import '../../domain/models/ledger_transaction.dart';
import '../../domain/models/transaction_type.dart';
import '../../domain/statistics/statistics_date_range.dart';
import '../../domain/statistics/statistics_summary.dart';
import '../../domain/validation/transaction_validator.dart';
import '../../shared/clock.dart';
import '../sqlite/transaction_local_data_source.dart';

final class TransactionRepository {
  TransactionRepository(this._dataSource, {Clock? clock})
    : _clock = clock ?? const SystemClock();

  final TransactionLocalDataSource _dataSource;
  final Clock _clock;

  Future<LedgerTransaction> create(NewLedgerTransaction input) async {
    final normalized = TransactionValidator.normalizeCreate(input);
    TransactionValidator.validateCreate(normalized, _clock);
    return _dataSource.insert(normalized, now: _clock.now());
  }

  Future<List<LedgerTransaction>> createBatch(
    Iterable<NewLedgerTransaction> inputs,
  ) async {
    final normalized = inputs
        .map(TransactionValidator.normalizeCreate)
        .toList(growable: false);
    if (normalized.isEmpty) {
      throw const TransactionValidationException('批量记账至少需要一笔账目');
    }
    for (final input in normalized) {
      TransactionValidator.validateCreate(input, _clock);
    }
    return _dataSource.insertBatch(normalized, now: _clock.now());
  }

  Future<List<LedgerTransaction>> createImportedBatch({
    required String source,
    required String fingerprint,
    required String fileName,
    required Iterable<NewLedgerTransaction> inputs,
  }) async {
    final normalized = inputs
        .map(TransactionValidator.normalizeCreate)
        .toList(growable: false);
    if (normalized.isEmpty) {
      throw const TransactionValidationException('导入批次至少需要一笔账目');
    }
    if (source.trim().isEmpty ||
        fingerprint.trim().isEmpty ||
        fileName.trim().isEmpty) {
      throw const TransactionValidationException('导入批次元数据无效');
    }
    for (final input in normalized) {
      TransactionValidator.validateCreate(input, _clock);
    }
    return _dataSource.insertImportedBatch(
      source: source.trim(),
      fingerprint: fingerprint.trim(),
      fileName: fileName.trim(),
      transactions: normalized,
      now: _clock.now(),
    );
  }

  Future<LedgerTransaction?> findById(int id, {bool includeDeleted = false}) {
    return _dataSource.findById(id, includeDeleted: includeDeleted);
  }

  Future<LedgerTransaction?> update(
    int id,
    LedgerTransactionUpdate input,
  ) async {
    final existing = await _dataSource.findById(id, includeDeleted: true);
    if (existing == null) {
      return null;
    }

    final normalized = TransactionValidator.normalizeUpdate(input);
    if (!normalized.hasChanges) {
      return existing;
    }

    TransactionValidator.validateUpdateCandidate(
      existing: existing,
      update: normalized,
      clock: _clock,
    );
    return _dataSource.update(id, normalized, now: _clock.now());
  }

  Future<LedgerTransaction?> softDelete(int id) {
    return _dataSource.softDelete(id, now: _clock.now());
  }

  Future<LedgerTransaction?> restore(int id) {
    return _dataSource.restore(id, now: _clock.now());
  }

  Future<List<LedgerTransaction>> list({int limit = 20, int offset = 0}) {
    _validatePaging(limit: limit, offset: offset);
    return _dataSource.listActive(limit: limit, offset: offset);
  }

  Future<List<LedgerTransaction>> recent({int limit = 5}) {
    _validatePaging(limit: limit, offset: 0);
    return _dataSource.listActive(limit: limit, offset: 0);
  }

  Future<List<LedgerTransaction>> activeTransactionsForDateRange({
    required String startDateInclusive,
    required String endDateExclusive,
  }) {
    final start = startDateInclusive.trim();
    final end = endDateExclusive.trim();
    final parsedStart = DateTime.tryParse(start);
    final parsedEnd = DateTime.tryParse(end);
    if (parsedStart == null ||
        parsedEnd == null ||
        !parsedStart.isBefore(parsedEnd)) {
      throw const TransactionValidationException('统计日期范围无效');
    }
    return _dataSource.listActiveInDateRange(
      startDateInclusive: start,
      endDateExclusive: _clampEndDateExclusive(end),
    );
  }

  Future<LedgerTransaction?> findLatestDuplicateCandidate(
    NewLedgerTransaction input,
  ) async {
    final normalized = TransactionValidator.normalizeCreate(input);
    TransactionValidator.validateCreate(normalized, _clock);
    return _dataSource.findLatestMatchingActive(
      amountCents: normalized.amountCents,
      type: normalized.type,
      category: normalized.category,
      note: normalized.note,
      transactionDate: normalized.transactionDate,
    );
  }

  Future<StatisticsSummary> statisticsForDateRange(
    StatisticsDateRange range,
  ) async {
    final data = await _dataSource.queryStatistics(
      startDateInclusive: range.startDateInclusive,
      endDateExclusive: _clampEndDateExclusive(range.endDateExclusive),
    );
    return StatisticsSummary.calculate(
      range: range,
      expenseTotalCents: data.expenseTotalCents,
      incomeTotalCents: data.incomeTotalCents,
      expenseCategories: data.expenseCategories.map(
        (category) => StatisticsCategoryAmount(
          categoryCode: category.categoryCode,
          amountCents: category.amountCents,
        ),
      ),
    );
  }

  Future<StatisticsSummary> currentMonthStatistics() {
    return statisticsForDateRange(StatisticsDateRange.month(_clock.now()));
  }

  Future<int> todayExpenseCents() {
    return _dataSource.sumActiveByTypeOnDate(
      type: TransactionType.expense,
      date: formatLocalDate(_clock.now()),
    );
  }

  Future<int> monthExpenseCents() {
    final range = _currentMonthRange();
    return _dataSource.sumActiveByTypeInDateRange(
      type: TransactionType.expense,
      startDateInclusive: range.start,
      endDateExclusive: range.end,
    );
  }

  Future<int> monthIncomeCents() {
    final range = _currentMonthRange();
    return _dataSource.sumActiveByTypeInDateRange(
      type: TransactionType.income,
      startDateInclusive: range.start,
      endDateExclusive: range.end,
    );
  }

  ({String start, String end}) _currentMonthRange() {
    final now = _clock.now();
    final start = DateTime(now.year, now.month);
    final end = DateTime(now.year, now.month + 1);
    return (
      start: formatLocalDate(start),
      end: _clampEndDateExclusive(formatLocalDate(end)),
    );
  }

  String _clampEndDateExclusive(String endDateExclusive) {
    final parsedEnd = DateTime.tryParse(endDateExclusive);
    if (parsedEnd == null) {
      return endDateExclusive;
    }

    final now = _clock.now();
    final tomorrow = DateTime(now.year, now.month, now.day + 1);
    if (parsedEnd.isAfter(tomorrow)) {
      return formatLocalDate(tomorrow);
    }
    return endDateExclusive;
  }

  static void _validatePaging({required int limit, required int offset}) {
    if (limit <= 0) {
      throw const TransactionValidationException('分页 limit 必须大于 0');
    }
    if (offset < 0) {
      throw const TransactionValidationException('分页 offset 不能小于 0');
    }
  }
}

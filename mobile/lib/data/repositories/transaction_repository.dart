import '../../domain/models/ledger_transaction.dart';
import '../../domain/models/transaction_type.dart';
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
    return (start: formatLocalDate(start), end: formatLocalDate(end));
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

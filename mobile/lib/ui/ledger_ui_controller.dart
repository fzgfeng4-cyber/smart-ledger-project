import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/backup/backup_service.dart';
import '../data/budget/budget_repository.dart';
import '../data/repositories/transaction_repository.dart';
import '../data/search/transaction_search_repository.dart';
import '../domain/categories/category_catalog.dart';
import '../domain/budget/budget.dart';
import '../domain/budget/budget_calculation.dart';
import '../domain/budget/budget_validator.dart';
import '../domain/classification/local_classification_service.dart';
import '../domain/classification/local_classification_suggestion.dart';
import '../domain/models/ledger_transaction.dart';
import '../domain/models/transaction_type.dart';
import '../domain/search/transaction_search_query.dart';
import '../domain/statistics/statistics_summary.dart';
import '../domain/parser/batch_parse_result.dart';
import '../domain/parser/multi_transaction_parser.dart';
import '../domain/parser/parse_result.dart';
import '../domain/parser/transaction_parser.dart';
import '../domain/validation/transaction_validator.dart';
import '../shared/clock.dart';
import 'models/ledger_ui_models.dart';
import 'shared/ledger_formatters.dart';

enum LedgerTransactionSaveStatus {
  idle,
  saved,
  savedWithRefreshFailure,
  failed;

  bool get isSaved =>
      this == LedgerTransactionSaveStatus.saved ||
      this == LedgerTransactionSaveStatus.savedWithRefreshFailure;
}

final class LedgerUiController extends ChangeNotifier {
  LedgerUiController({
    required this.repository,
    required this.searchRepository,
    required this.backupService,
    required this.budgetRepository,
    TransactionParser? parser,
    MultiTransactionParser? multiTransactionParser,
    TransactionSearchQueryParser? searchQueryParser,
    LocalClassificationService? localClassificationService,
    Clock? clock,
    DateTime? today,
    this.pageSize = 20,
  }) : _clock = clock ?? const SystemClock(),
       _parser =
           parser ?? TransactionParser(clock: clock ?? const SystemClock()),
       _multiTransactionParser =
           multiTransactionParser ??
           MultiTransactionParser(clock: clock ?? const SystemClock()),
       _searchQueryParser =
           searchQueryParser ?? const TransactionSearchQueryParser(),
       _localClassificationService =
           localClassificationService ?? const LocalClassificationService(),
       _today = _dateOnly(today ?? (clock ?? const SystemClock()).now());

  final TransactionRepository repository;
  final TransactionSearchRepository searchRepository;
  final BackupService backupService;
  final BudgetRepository budgetRepository;
  final TransactionParser _parser;
  final MultiTransactionParser _multiTransactionParser;
  final TransactionSearchQueryParser _searchQueryParser;
  final LocalClassificationService _localClassificationService;
  final Clock _clock;
  final DateTime _today;
  final int pageSize;
  final List<UiLedgerEntry> _entries = [];
  final List<UiLedgerEntry> _searchEntries = [];

  int _todayExpenseCents = 0;
  int _monthExpenseCents = 0;
  int _monthIncomeCents = 0;
  bool _hasMoreEntries = false;
  bool _initialized = false;
  bool _isBusy = false;
  bool _isOperationBusy = false;
  bool _disposed = false;
  bool _isBackupBusy = false;
  bool _isSearching = false;
  bool _isStatisticsBusy = false;
  bool _isBudgetBusy = false;
  bool _statisticsInitialized = false;
  bool _statisticsRefreshPending = false;
  bool _budgetInitialized = false;
  bool _failNextLoadMore = false;
  bool _failNextRefresh = false;
  bool _failNextBudgetRefresh = false;
  var _listStatus = LedgerListStatus.loading;
  String? _loadError;
  String? _quickInputError;
  String? _feedbackMessage;
  String? _searchQueryText;
  String? _searchError;
  String? _statisticsError;
  String? _budgetError;
  String? _budgetFeedback;
  var _transactionSaveStatus = LedgerTransactionSaveStatus.idle;
  StatisticsSummary? _statisticsSummary;
  final List<BudgetCalculation> _budgetCalculations = [];
  EditorDraft? _draft;
  BatchParseResult? _batchDraft;
  LocalClassificationSuggestion? _classificationSuggestion;
  UndoDeleteState? _undoDeleteState;
  Timer? _undoTimer;

  DateTime get today => _today;

  LedgerListStatus get listStatus => _listStatus;

  bool get isBusy => _isBusy || _isOperationBusy;

  bool get isBackupBusy => _isBackupBusy || _isOperationBusy;

  bool get isSearching => _isSearching;

  bool get isStatisticsBusy => _isStatisticsBusy;

  bool get isStatisticsRefreshPending => _statisticsRefreshPending;

  bool get hasRequestedStatistics => _statisticsInitialized;

  bool get isBudgetBusy => _isBudgetBusy || _isOperationBusy;

  String? get loadError => _loadError;

  String? get quickInputError => _quickInputError;

  String? get feedbackMessage => _feedbackMessage;

  String? get searchError => _searchError;

  String? get statisticsError => _statisticsError;

  String? get budgetError => _budgetError;

  String? get budgetFeedback => _budgetFeedback;

  LedgerTransactionSaveStatus get transactionSaveStatus =>
      _transactionSaveStatus;

  StatisticsSummary? get statisticsSummary => _statisticsSummary;

  List<BudgetCalculation> get budgetCalculations {
    return List.unmodifiable(_budgetCalculations);
  }

  String get budgetMonth => _formatMonth(_today);

  bool get hasActiveSearch {
    final query = _searchQueryText;
    return query != null && query.trim().isNotEmpty;
  }

  String? get searchQueryText => _searchQueryText;

  String? get searchStatusMessage {
    if (!hasActiveSearch) {
      return null;
    }
    if (_isSearching) {
      return '搜索中...';
    }
    if (_searchError != null) {
      return _searchError;
    }
    if (_searchEntries.isEmpty) {
      return '没有找到符合条件的账目。';
    }
    return '找到 ${_searchEntries.length} 笔账目。';
  }

  List<UiLedgerEntry> get searchEntries {
    return List.unmodifiable(_searchEntries);
  }

  EditorDraft? get draft => _draft;

  BatchParseResult? get batchDraft => _batchDraft;

  LocalClassificationSuggestion? get classificationSuggestion =>
      _classificationSuggestion;

  UndoDeleteState? get undoDeleteState => _undoDeleteState;

  bool get hasUnsavedDraft {
    final draft = _draft;
    if (draft == null) {
      return false;
    }
    if (draft.mode == EditorMode.create) {
      return draft.originalText.trim().isNotEmpty || draft.isDirty;
    }
    return draft.isDirty;
  }

  List<UiLedgerEntry> get visibleEntries => List.unmodifiable(_entries);

  List<UiLedgerEntry> get recentEntries {
    return List.unmodifiable(_entries.take(5));
  }

  bool get hasMoreEntries => _hasMoreEntries;

  int get todayExpenseCents => _todayExpenseCents;

  int get monthExpenseCents => _monthExpenseCents;

  int get monthIncomeCents => _monthIncomeCents;

  List<CategoryDefinition> get categoryOptions {
    final type = _draft?.type;
    if (type == null) {
      return const [];
    }
    return CategoryCatalog.forType(type);
  }

  String? get validationMessage {
    final draft = _draft;
    if (draft == null) {
      return null;
    }
    if (draft.issues.any((issue) => issue.code == 'MULTIPLE_AMOUNTS')) {
      return '请把多笔账拆成一笔后再保存。';
    }
    if (draft.issues.any((issue) => issue.code == 'TYPE_CONFLICT')) {
      return '这句话同时包含收入和支出，请改成一笔账。';
    }
    final amountCents = parseYuanToCents(draft.amountText);
    if (amountCents == null) {
      return '请输入大于 0 的金额。';
    }
    if (draft.type == null) {
      return '请选择收入或支出。';
    }
    if (draft.category == null) {
      return '请选择分类。';
    }
    if (!CategoryCatalog.isValidForType(draft.type!, draft.category!)) {
      return '分类与收支不匹配，请重新选择。';
    }
    if (DateTime.tryParse(draft.transactionDate) == null) {
      return '请输入有效日期。';
    }
    if (isFutureDate(draft.transactionDate, _today)) {
      return '这个日期在未来，请检查日期。';
    }
    if (draft.hasUnresolvedReviewIssue) {
      return '请先处理待确认提示。';
    }
    return null;
  }

  bool get canSaveDraft {
    return !_isBusy && _draft != null && validationMessage == null;
  }

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }
    _initialized = true;
    _budgetInitialized = true;
    await refresh();
  }

  Future<void> refresh() async {
    if (isBusy || !_beginOperation()) {
      return;
    }
    try {
      await _loadData(showBusyState: true);
    } finally {
      _endOperation();
      notifyListeners();
    }
  }

  bool prepareDraftFromInput(String input) {
    _quickInputError = null;
    _feedbackMessage = null;
    _transactionSaveStatus = LedgerTransactionSaveStatus.idle;
    if (input.trim().isEmpty) {
      _quickInputError = '请输入一笔账，例如：35块买菜。';
      notifyListeners();
      return false;
    }

    final result = _applyLocalClassification(
      input,
      _parser.parse(input, today: _today),
    );
    final parsed = result.draft;
    if (parsed == null) {
      _quickInputError = '暂时无法识别这句话，请补充金额、事项或收支信息。';
      notifyListeners();
      return false;
    }

    _draft = EditorDraft(
      originalText: result.originalText,
      amountText: parsed.amountCents == null
          ? ''
          : formatAmountInput(parsed.amountCents!),
      type: parsed.type,
      category: parsed.category,
      note: parsed.note ?? '',
      transactionDate: parsed.transactionDate ?? formatIsoDate(_today),
      issues: result.issues.map(_toUiIssue).toList(),
      mode: EditorMode.create,
    );
    notifyListeners();
    return true;
  }

  bool prepareBatchDraftFromInput(String input) {
    _quickInputError = null;
    _feedbackMessage = null;
    _transactionSaveStatus = LedgerTransactionSaveStatus.idle;
    if (input.trim().isEmpty) {
      _quickInputError = '请输入多笔账，例如：买菜35元\n加油300元。';
      notifyListeners();
      return false;
    }

    _batchDraft = _multiTransactionParser.parse(input, today: _today);
    notifyListeners();
    return true;
  }

  void startCreateBlank() {
    _draft = EditorDraft(
      originalText: '',
      amountText: '',
      type: null,
      category: null,
      note: '',
      transactionDate: formatIsoDate(_today),
      issues: const [],
      mode: EditorMode.create,
    );
    _feedbackMessage = null;
    _transactionSaveStatus = LedgerTransactionSaveStatus.idle;
    notifyListeners();
  }

  void startEditing(UiLedgerEntry entry) {
    _draft = EditorDraft(
      originalText: entry.originalText,
      amountText: formatAmountInput(entry.amountCents),
      type: entry.type,
      category: entry.category,
      note: entry.note ?? '',
      transactionDate: entry.transactionDate,
      issues: const [],
      mode: EditorMode.edit,
      sourceEntryId: entry.id,
    );
    _feedbackMessage = null;
    _transactionSaveStatus = LedgerTransactionSaveStatus.idle;
    notifyListeners();
  }

  void updateAmountText(String value) {
    final draft = _draft;
    if (draft == null) {
      return;
    }
    draft.amountText = value;
    if (parseYuanToCents(value) != null) {
      draft.acknowledgedIssueCodes.addAll(const {
        'MISSING_AMOUNT',
        'INVALID_AMOUNT',
      });
    }
    notifyListeners();
  }

  void updateType(TransactionType type) {
    final draft = _draft;
    if (draft == null) {
      return;
    }
    draft.type = type;
    draft.acknowledgedIssueCodes.add('TYPE_UNKNOWN');
    if (draft.category != null &&
        !CategoryCatalog.isValidForType(type, draft.category!)) {
      draft.category = null;
    }
    notifyListeners();
  }

  void updateCategory(String code) {
    final draft = _draft;
    if (draft == null) {
      return;
    }
    draft.category = code;
    draft.acknowledgedIssueCodes.addAll(
      draft.issues
          .where((issue) => issue.field == 'category')
          .map((issue) => issue.code),
    );
    notifyListeners();
  }

  void updateNote(String value) {
    _draft?.note = value;
    notifyListeners();
  }

  void updateDate(String value) {
    final draft = _draft;
    if (draft == null) {
      return;
    }
    draft.transactionDate = value;
    if (DateTime.tryParse(value) != null && !isFutureDate(value, _today)) {
      draft.acknowledgedIssueCodes.addAll(const {
        'INVALID_DATE',
        'UNSUPPORTED_DATE',
        'FUTURE_DATE',
      });
    }
    notifyListeners();
  }

  void acknowledgeIssue(String code) {
    _draft?.acknowledgedIssueCodes.add(code);
    notifyListeners();
  }

  String? get editorErrorMessage => _feedbackMessage;

  Future<bool> saveDraft() async {
    final draft = _draft;
    _transactionSaveStatus = LedgerTransactionSaveStatus.idle;
    if (draft == null || !canSaveDraft || !_beginOperation()) {
      notifyListeners();
      return false;
    }

    _isBusy = true;
    _feedbackMessage = null;
    notifyListeners();

    try {
      final amountCents = parseYuanToCents(draft.amountText);
      final type = draft.type;
      final category = draft.category;
      if (amountCents == null || type == null || category == null) {
        _transactionSaveStatus = LedgerTransactionSaveStatus.failed;
        return false;
      }

      final note = draft.note.trim().isEmpty ? null : draft.note.trim();
      if (draft.mode == EditorMode.edit && draft.sourceEntryId != null) {
        final updated = await repository.update(
          draft.sourceEntryId!,
          LedgerTransactionUpdate(
            amountCents: amountCents,
            type: type,
            category: category,
            note: note,
            transactionDate: draft.transactionDate,
          ),
        );
        if (updated == null) {
          _transactionSaveStatus = LedgerTransactionSaveStatus.failed;
          _feedbackMessage = '这笔账已不存在或已被删除，请刷新后重试。';
          return false;
        }
        _feedbackMessage = '修改已保存。';
      } else {
        await repository.create(
          NewLedgerTransaction(
            amountCents: amountCents,
            type: type,
            category: category,
            note: note,
            originalText: draft.originalText.trim().isEmpty
                ? '手动新建'
                : draft.originalText,
            transactionDate: draft.transactionDate,
          ),
        );
        _feedbackMessage = '已记账 ${formatMoneyCents(amountCents)}。';
      }

      _transactionSaveStatus = LedgerTransactionSaveStatus.saved;
      final refreshed = await _loadData(showBusyState: false);
      if (!refreshed) {
        _transactionSaveStatus =
            LedgerTransactionSaveStatus.savedWithRefreshFailure;
        _draft = null;
        _feedbackMessage = '账目已保存，但列表刷新失败，请返回列表确认，避免重复提交。';
        return true;
      }
      _draft = null;
      return true;
    } on TransactionValidationException catch (error) {
      _transactionSaveStatus = LedgerTransactionSaveStatus.failed;
      _feedbackMessage = error.message;
      return false;
    } catch (_) {
      _transactionSaveStatus = LedgerTransactionSaveStatus.failed;
      _feedbackMessage = '保存失败，请稍后重试。';
      return false;
    } finally {
      _isBusy = false;
      _endOperation();
      notifyListeners();
    }
  }

  Future<bool> saveBatchTransactions(
    Iterable<NewLedgerTransaction> transactions,
  ) async {
    _transactionSaveStatus = LedgerTransactionSaveStatus.idle;
    if (isBusy || isBackupBusy || !_beginOperation()) {
      return false;
    }

    _isBusy = true;
    _feedbackMessage = null;
    notifyListeners();
    try {
      final saved = await repository.createBatch(transactions);
      _feedbackMessage = '已批量记账 ${saved.length} 笔。';
      _batchDraft = null;
      final refreshed = await _loadData(showBusyState: false);
      if (!refreshed) {
        _transactionSaveStatus =
            LedgerTransactionSaveStatus.savedWithRefreshFailure;
        _feedbackMessage = '批量账目已保存，但列表刷新失败，请返回列表确认，避免重复提交。';
        return true;
      }
      _transactionSaveStatus = LedgerTransactionSaveStatus.saved;
      return true;
    } on TransactionValidationException catch (error) {
      _transactionSaveStatus = LedgerTransactionSaveStatus.failed;
      _feedbackMessage = error.message;
      return false;
    } catch (_) {
      _transactionSaveStatus = LedgerTransactionSaveStatus.failed;
      _feedbackMessage = '批量保存失败，未写入任何账目。';
      return false;
    } finally {
      _isBusy = false;
      _endOperation();
      notifyListeners();
    }
  }

  void discardBatchDraft() {
    _batchDraft = null;
    notifyListeners();
  }

  void discardEditorChanges() {
    _draft = null;
    _transactionSaveStatus = LedgerTransactionSaveStatus.idle;
    notifyListeners();
  }

  Future<void> search(String input) async {
    final normalized = input.trim();
    if (normalized.isEmpty) {
      clearSearch();
      return;
    }

    final query = _parseSearchQuery(normalized);
    if (query == null) {
      _searchQueryText = normalized;
      _searchEntries.clear();
      _searchError = '搜索条件无法识别，请检查后重试。';
      _isSearching = false;
      notifyListeners();
      return;
    }
    if (query.isEmpty) {
      clearSearch();
      return;
    }

    if (isBusy || isBackupBusy || _isSearching || !_beginOperation()) {
      return;
    }

    _searchQueryText = normalized;
    _searchError = null;
    _isSearching = true;
    notifyListeners();

    try {
      await _syncSearchResults(parsedQuery: query);
    } finally {
      _isSearching = false;
      _endOperation();
      notifyListeners();
    }
  }

  void clearSearch() {
    _searchQueryText = null;
    _searchError = null;
    _searchEntries.clear();
    _isSearching = false;
    notifyListeners();
  }

  Future<void> refreshStatistics() async {
    _statisticsInitialized = true;
    _statisticsRefreshPending = true;
    if (_isStatisticsBusy || isBusy || isBackupBusy || !_beginOperation()) {
      notifyListeners();
      return;
    }

    _statisticsRefreshPending = false;
    _isStatisticsBusy = true;
    _statisticsError = null;
    notifyListeners();
    try {
      _statisticsSummary = await repository.currentMonthStatistics();
    } catch (_) {
      _statisticsSummary = null;
      _statisticsError = '统计加载失败，请重试。';
    } finally {
      _isStatisticsBusy = false;
      _endOperation();
      notifyListeners();
    }
  }

  Future<void> refreshBudgets() async {
    if (_isBudgetBusy || isBusy || isBackupBusy || !_beginOperation()) {
      return;
    }

    _budgetInitialized = true;
    try {
      await _loadBudgets(showBusyState: true);
    } finally {
      _endOperation();
      notifyListeners();
    }
  }

  Future<bool> createBudget(NewBudget input) async {
    if (_isBudgetBusy || isBusy || isBackupBusy || !_beginOperation()) {
      return false;
    }

    _isBudgetBusy = true;
    _budgetError = null;
    _budgetFeedback = null;
    notifyListeners();
    try {
      await budgetRepository.create(input);
      _budgetFeedback = '预算已保存。';
      await _loadBudgets(showBusyState: false);
      return true;
    } on BudgetValidationException catch (error) {
      _budgetError = error.message;
      return false;
    } catch (_) {
      _budgetError = '预算保存失败，请重试。';
      return false;
    } finally {
      _isBudgetBusy = false;
      _endOperation();
      notifyListeners();
    }
  }

  Future<bool> updateBudget(int id, BudgetUpdate input) async {
    if (_isBudgetBusy || isBusy || isBackupBusy || !_beginOperation()) {
      return false;
    }

    _isBudgetBusy = true;
    _budgetError = null;
    _budgetFeedback = null;
    notifyListeners();
    try {
      final updated = await budgetRepository.update(id, input);
      if (updated == null) {
        _budgetError = '预算已不存在，请刷新后重试。';
        return false;
      }
      _budgetFeedback = '预算已更新。';
      await _loadBudgets(showBusyState: false);
      return true;
    } on BudgetValidationException catch (error) {
      _budgetError = error.message;
      return false;
    } catch (_) {
      _budgetError = '预算更新失败，请重试。';
      return false;
    } finally {
      _isBudgetBusy = false;
      _endOperation();
      notifyListeners();
    }
  }

  Future<bool> disableBudget(int id) {
    return updateBudget(id, const BudgetUpdate(enabled: false));
  }

  Future<void> loadMore() async {
    if (isBusy || !_initialized || !_hasMoreEntries || !_beginOperation()) {
      return;
    }

    _isBusy = true;
    _listStatus = LedgerListStatus.loading;
    _loadError = null;
    notifyListeners();

    try {
      if (_failNextLoadMore) {
        _failNextLoadMore = false;
        throw StateError('测试用加载更多失败');
      }

      final rows = await repository.list(
        limit: pageSize,
        offset: _entries.length,
      );
      _entries.addAll(rows.map(_toUiEntry));
      _hasMoreEntries = rows.length == pageSize;
      _listStatus = _hasMoreEntries
          ? LedgerListStatus.idle
          : LedgerListStatus.end;
    } catch (error) {
      _loadError = _toUserError(error);
      _listStatus = LedgerListStatus.error;
    } finally {
      _isBusy = false;
      _endOperation();
      notifyListeners();
    }
  }

  Future<void> retryLoadMore() async {
    if (_entries.isEmpty) {
      await refresh();
      return;
    }
    await loadMore();
  }

  void failNextLoadMoreForTest() {
    _failNextLoadMore = true;
  }

  void failNextRefreshForTest() {
    _failNextRefresh = true;
  }

  void failNextBudgetRefreshForTest() {
    _failNextBudgetRefresh = true;
  }

  Future<bool> deleteCurrentEntry() async {
    final draft = _draft;
    final id = draft?.sourceEntryId;
    if (id == null || isBusy || !_beginOperation()) {
      return false;
    }

    _isBusy = true;
    _feedbackMessage = null;
    notifyListeners();

    try {
      final deleted = await repository.softDelete(id);
      if (deleted == null) {
        _feedbackMessage = '这笔账已不存在或已被删除。';
        return false;
      }

      final uiEntry = _toUiEntry(deleted);
      _undoDeleteState = UndoDeleteState(
        entry: uiEntry,
        expiresAt: _clock.now().add(const Duration(seconds: 10)),
      );
      _feedbackMessage = '已删除这笔账。';
      _draft = null;
      _startUndoExpiryTimer();
      await _loadData(showBusyState: false);
      return true;
    } catch (error) {
      _feedbackMessage = _toUserError(error);
      return false;
    } finally {
      _isBusy = false;
      _endOperation();
      notifyListeners();
    }
  }

  Future<bool> undoDelete() async {
    final undoState = _undoDeleteState;
    if (undoState == null || isBusy || !_beginOperation()) {
      return false;
    }

    _isBusy = true;
    notifyListeners();
    try {
      final restored = await repository.restore(undoState.entry.id);
      if (restored == null) {
        _feedbackMessage = '撤销失败，这笔账可能已不存在。';
        return false;
      }
      _undoTimer?.cancel();
      _undoDeleteState = null;
      _feedbackMessage = '已恢复这笔账。';
      await _loadData(showBusyState: false);
      return true;
    } catch (error) {
      _feedbackMessage = _toUserError(error);
      return false;
    } finally {
      _isBusy = false;
      _endOperation();
      notifyListeners();
    }
  }

  void clearFeedback() {
    _feedbackMessage = null;
    notifyListeners();
  }

  Future<BackupExportResult> exportBackup() async {
    if (isBusy || isBackupBusy || !_beginOperation()) {
      throw const BackupException('备份正在处理中，请稍候。');
    }

    _isBackupBusy = true;
    notifyListeners();
    try {
      return await backupService.exportBackup();
    } finally {
      _isBackupBusy = false;
      _endOperation();
      notifyListeners();
    }
  }

  Future<List<BackupFileInfo>> listBackups() {
    return backupService.listBackups();
  }

  Future<BackupImportResult> importBackup(String filePath) async {
    if (isBusy || isBackupBusy || !_beginOperation()) {
      throw const BackupException('当前正在处理数据，请稍候。');
    }

    _isBackupBusy = true;
    notifyListeners();
    try {
      final result = await backupService.importBackup(filePath);
      await _loadData(showBusyState: true);
      return result;
    } finally {
      _isBackupBusy = false;
      _endOperation();
      notifyListeners();
    }
  }

  Future<bool> _loadData({required bool showBusyState}) async {
    if (showBusyState) {
      _isBusy = true;
    }
    _listStatus = LedgerListStatus.loading;
    _loadError = null;
    notifyListeners();

    try {
      if (_failNextRefresh) {
        _failNextRefresh = false;
        throw StateError('测试用刷新失败');
      }

      final rows = await repository.list(limit: pageSize, offset: 0);
      final summaries = await Future.wait<int>([
        repository.todayExpenseCents(),
        repository.monthExpenseCents(),
        repository.monthIncomeCents(),
      ]);

      _entries
        ..clear()
        ..addAll(rows.map(_toUiEntry));
      _todayExpenseCents = summaries[0];
      _monthExpenseCents = summaries[1];
      _monthIncomeCents = summaries[2];
      _hasMoreEntries = rows.length == pageSize;
      _listStatus = _hasMoreEntries
          ? LedgerListStatus.idle
          : LedgerListStatus.end;
      final searchText = _searchQueryText;
      if (searchText == null || searchText.trim().isEmpty) {
        _searchEntries.clear();
        _searchError = null;
      } else {
        await _syncSearchResults();
      }
      if (_statisticsInitialized) {
        await _syncStatisticsIfInitialized();
      }
      if (_budgetInitialized) {
        await _syncBudgetsIfInitialized();
      }
      return true;
    } catch (error) {
      _loadError = _toUserError(error);
      _listStatus = LedgerListStatus.error;
      return false;
    } finally {
      if (showBusyState) {
        _isBusy = false;
      }
      notifyListeners();
    }
  }

  void _startUndoExpiryTimer() {
    _undoTimer?.cancel();
    _undoTimer = Timer(const Duration(seconds: 10), () {
      _undoDeleteState = null;
      notifyListeners();
    });
  }

  UiLedgerEntry _toUiEntry(LedgerTransaction entry) {
    return UiLedgerEntry(
      id: entry.id,
      amountCents: entry.amountCents,
      type: entry.type,
      category: entry.category,
      note: entry.note,
      originalText: entry.originalText,
      transactionDate: entry.transactionDate,
      deletedAt: entry.deletedAt,
    );
  }

  UiIssue _toUiIssue(ParseIssue issue) {
    return UiIssue(
      code: issue.code,
      message: issue.message,
      severity: issue.isBlocking
          ? UiIssueSeverity.blocking
          : UiIssueSeverity.review,
      field: issue.field,
      candidates: issue.candidates,
    );
  }

  ParseResult _applyLocalClassification(String input, ParseResult result) {
    final suggestion = _localClassificationService.suggest(input);
    _classificationSuggestion = suggestion;

    final suggestionAmount = suggestion.amountCents;
    final suggestionType = suggestion.type;
    final suggestionCategory = suggestion.categoryCode;
    final canUseSuggestion =
        suggestionAmount != null &&
        suggestionType != null &&
        suggestionCategory != null &&
        CategoryCatalog.isValidForType(suggestionType, suggestionCategory) &&
        !result.hasIssue('MULTIPLE_AMOUNTS') &&
        !result.hasIssue('TYPE_CONFLICT');
    if (!canUseSuggestion) {
      return result;
    }

    final parsed = result.draft;
    final categoryNeedsSuggestion =
        parsed?.category == null ||
        parsed?.category == 'other_expense' ||
        parsed?.category == 'other_income';
    final usedSuggestion =
        parsed?.amountCents == null ||
        parsed?.type == null ||
        categoryNeedsSuggestion;
    if (!usedSuggestion) {
      return result;
    }

    final merged = TransactionDraft(
      amountCents: parsed?.amountCents ?? suggestionAmount,
      type: parsed?.type ?? suggestionType,
      category: categoryNeedsSuggestion ? suggestionCategory : parsed?.category,
      note: parsed?.note,
      originalText: parsed?.originalText ?? result.originalText,
      transactionDate: parsed?.transactionDate ?? formatLocalDate(_today),
    );
    final issues = result.issues.where((issue) {
      if (issue.code == 'TYPE_UNKNOWN' && parsed?.type == null) {
        return false;
      }
      if ((issue.code == 'MISSING_CATEGORY' ||
              issue.code == 'CATEGORY_FALLBACK') &&
          categoryNeedsSuggestion) {
        return false;
      }
      return true;
    }).toList();
    final label =
        CategoryCatalog.findByCode(suggestionCategory)?.label ??
        suggestionCategory;
    issues.add(
      ParseIssue(
        code: 'LOCAL_CLASSIFICATION_SUGGESTION',
        field: 'category',
        message: '已根据本地规则建议分类为“$label”，请确认后再保存。',
        candidates: [suggestionCategory],
      ),
    );

    final missingFields = <String>[
      if (merged.amountCents == null) 'amount_cents',
      if (merged.type == null) 'type',
      if (merged.category == null) 'category',
      if (merged.transactionDate == null) 'transaction_date',
    ];
    final status =
        missingFields.isNotEmpty || issues.any((issue) => issue.isBlocking)
        ? ParseStatus.needsInput
        : ParseStatus.needsConfirmation;
    return ParseResult(
      status: status,
      originalText: result.originalText,
      draft: merged,
      missingFields: missingFields,
      issues: issues,
    );
  }

  String _toUserError(Object error) {
    if (error is TransactionValidationException) {
      return error.message;
    }
    return '数据加载失败，请重试。';
  }

  Future<void> _syncSearchResults({TransactionSearchQuery? parsedQuery}) async {
    final queryText = _searchQueryText;
    if (queryText == null || queryText.trim().isEmpty) {
      _searchEntries.clear();
      _searchError = null;
      return;
    }

    final query = parsedQuery ?? _parseSearchQuery(queryText);
    if (query == null) {
      _searchEntries.clear();
      _searchError = '搜索条件无法识别，请检查后重试。';
      return;
    }
    if (query.isEmpty) {
      _searchEntries.clear();
      _searchError = null;
      return;
    }

    try {
      final rows = await searchRepository.search(query, limit: 50);
      _searchEntries
        ..clear()
        ..addAll(rows.map(_toUiEntry));
      _searchError = null;
    } catch (error) {
      _searchEntries.clear();
      _searchError = _toUserError(error);
    }
  }

  TransactionSearchQuery? _parseSearchQuery(String input) {
    try {
      return _searchQueryParser.parse(input, today: _today);
    } on Object {
      return null;
    }
  }

  Future<void> _syncStatisticsIfInitialized() async {
    if (!_statisticsInitialized) {
      return;
    }
    if (_isStatisticsBusy) {
      _statisticsRefreshPending = true;
      return;
    }
    _statisticsRefreshPending = false;
    try {
      _statisticsSummary = await repository.currentMonthStatistics();
      _statisticsError = null;
    } catch (_) {
      _statisticsSummary = null;
      _statisticsError = '统计加载失败，请重试。';
    }
  }

  Future<void> _loadBudgets({required bool showBusyState}) async {
    if (showBusyState) {
      _isBudgetBusy = true;
    }
    _budgetError = null;
    notifyListeners();

    try {
      if (_failNextBudgetRefresh) {
        _failNextBudgetRefresh = false;
        throw StateError('测试用预算加载失败');
      }

      final month = budgetMonth;
      final start = DateTime(_today.year, _today.month);
      final end = DateTime(_today.year, _today.month + 1);
      final budgets = await budgetRepository.listForMonth(month);
      final transactions = await repository.activeTransactionsForDateRange(
        startDateInclusive: formatIsoDate(start),
        endDateExclusive: formatIsoDate(end),
      );
      _budgetCalculations
        ..clear()
        ..addAll(
          BudgetCalculationService(clock: _clock).calculate(
            month: month,
            budgets: budgets,
            transactions: transactions,
          ),
        );
    } catch (_) {
      _budgetCalculations.clear();
      _budgetError = '预算加载失败，请重试。';
    } finally {
      if (showBusyState) {
        _isBudgetBusy = false;
      }
      notifyListeners();
    }
  }

  Future<void> _syncBudgetsIfInitialized() async {
    if (!_budgetInitialized || _isBudgetBusy) {
      return;
    }
    await _loadBudgets(showBusyState: false);
  }

  bool _beginOperation() {
    if (_isOperationBusy) {
      return false;
    }
    _isOperationBusy = true;
    return true;
  }

  void _endOperation() {
    _isOperationBusy = false;
    if (_statisticsRefreshPending && !_isStatisticsBusy) {
      unawaited(_flushPendingStatisticsRefresh());
    }
  }

  Future<void> _flushPendingStatisticsRefresh() async {
    if (!_statisticsRefreshPending ||
        _isStatisticsBusy ||
        isBusy ||
        isBackupBusy) {
      return;
    }
    await refreshStatistics();
  }

  @override
  void dispose() {
    _disposed = true;
    _undoTimer?.cancel();
    super.dispose();
  }

  @override
  void notifyListeners() {
    if (_disposed) {
      return;
    }
    super.notifyListeners();
  }
}

DateTime _dateOnly(DateTime value) {
  return DateTime(value.year, value.month, value.day);
}

String _formatMonth(DateTime value) {
  return '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}';
}

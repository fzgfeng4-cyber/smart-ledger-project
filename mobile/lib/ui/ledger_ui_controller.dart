import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/backup/backup_service.dart';
import '../data/repositories/transaction_repository.dart';
import '../domain/categories/category_catalog.dart';
import '../domain/models/ledger_transaction.dart';
import '../domain/models/transaction_type.dart';
import '../domain/parser/parse_result.dart';
import '../domain/parser/transaction_parser.dart';
import '../domain/validation/transaction_validator.dart';
import '../shared/clock.dart';
import 'models/ledger_ui_models.dart';
import 'shared/ledger_formatters.dart';

final class LedgerUiController extends ChangeNotifier {
  LedgerUiController({
    required this.repository,
    required this.backupService,
    TransactionParser? parser,
    Clock? clock,
    DateTime? today,
    this.pageSize = 20,
  }) : _clock = clock ?? const SystemClock(),
       _parser =
           parser ?? TransactionParser(clock: clock ?? const SystemClock()),
       _today = _dateOnly(today ?? (clock ?? const SystemClock()).now());

  final TransactionRepository repository;
  final BackupService backupService;
  final TransactionParser _parser;
  final Clock _clock;
  final DateTime _today;
  final int pageSize;
  final List<UiLedgerEntry> _entries = [];

  int _todayExpenseCents = 0;
  int _monthExpenseCents = 0;
  int _monthIncomeCents = 0;
  bool _hasMoreEntries = false;
  bool _initialized = false;
  bool _isBusy = false;
  bool _isBackupBusy = false;
  bool _failNextLoadMore = false;
  bool _failNextRefresh = false;
  var _listStatus = LedgerListStatus.loading;
  String? _loadError;
  String? _quickInputError;
  String? _feedbackMessage;
  EditorDraft? _draft;
  UndoDeleteState? _undoDeleteState;
  Timer? _undoTimer;

  DateTime get today => _today;

  LedgerListStatus get listStatus => _listStatus;

  bool get isBusy => _isBusy;

  bool get isBackupBusy => _isBackupBusy;

  String? get loadError => _loadError;

  String? get quickInputError => _quickInputError;

  String? get feedbackMessage => _feedbackMessage;

  EditorDraft? get draft => _draft;

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
    await refresh();
  }

  Future<void> refresh() async {
    if (_isBusy) {
      return;
    }
    await _loadData(showBusyState: true);
  }

  bool prepareDraftFromInput(String input) {
    _quickInputError = null;
    _feedbackMessage = null;
    if (input.trim().isEmpty) {
      _quickInputError = '请输入一笔账，例如：35块买菜。';
      notifyListeners();
      return false;
    }

    final result = _parser.parse(input, today: _today);
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
    if (draft == null || !canSaveDraft) {
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

      await _loadData(showBusyState: false);
      _draft = null;
      return true;
    } on TransactionValidationException catch (error) {
      _feedbackMessage = error.message;
      return false;
    } catch (_) {
      _feedbackMessage = '保存失败，请稍后重试。';
      return false;
    } finally {
      _isBusy = false;
      notifyListeners();
    }
  }

  void discardEditorChanges() {
    _draft = null;
    notifyListeners();
  }

  Future<void> loadMore() async {
    if (_isBusy || !_initialized || !_hasMoreEntries) {
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

  Future<bool> deleteCurrentEntry() async {
    final draft = _draft;
    final id = draft?.sourceEntryId;
    if (id == null || _isBusy) {
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
      notifyListeners();
    }
  }

  Future<bool> undoDelete() async {
    final undoState = _undoDeleteState;
    if (undoState == null || _isBusy) {
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
      notifyListeners();
    }
  }

  void clearFeedback() {
    _feedbackMessage = null;
    notifyListeners();
  }

  Future<BackupExportResult> exportBackup() async {
    if (_isBackupBusy) {
      throw const BackupException('备份正在处理中，请稍候。');
    }

    _isBackupBusy = true;
    notifyListeners();
    try {
      return await backupService.exportBackup();
    } finally {
      _isBackupBusy = false;
      notifyListeners();
    }
  }

  Future<List<BackupFileInfo>> listBackups() {
    return backupService.listBackups();
  }

  Future<BackupImportResult> importBackup(String filePath) async {
    if (_isBackupBusy || _isBusy) {
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

  String _toUserError(Object error) {
    if (error is TransactionValidationException) {
      return error.message;
    }
    return '数据加载失败，请重试。';
  }

  @override
  void dispose() {
    _undoTimer?.cancel();
    super.dispose();
  }
}

DateTime _dateOnly(DateTime value) {
  return DateTime(value.year, value.month, value.day);
}

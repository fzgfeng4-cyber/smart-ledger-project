import 'dart:async';

import 'package:flutter/material.dart';

import '../../domain/categories/category_catalog.dart';
import '../../domain/models/ledger_transaction.dart';
import '../../domain/models/transaction_type.dart';
import '../../domain/parser/batch_parse_result.dart';
import '../../domain/parser/parse_result.dart';
import '../../domain/validation/transaction_validator.dart';
import '../shared/ledger_formatters.dart';

class BatchConfirmPage extends StatefulWidget {
  const BatchConfirmPage({
    required this.result,
    this.onConfirm,
    this.onSubmitFailureMessage,
    this.today,
    super.key,
  });

  final BatchParseResult result;
  final Future<bool> Function(List<NewLedgerTransaction> transactions)?
  onConfirm;
  final String? Function()? onSubmitFailureMessage;
  final DateTime? today;

  @override
  State<BatchConfirmPage> createState() => _BatchConfirmPageState();
}

class _BatchConfirmPageState extends State<BatchConfirmPage> {
  late final Map<int, _BatchRowDraft> _drafts;
  late final Set<int> _excludedIds;
  final Map<int, String?> _rowErrors = {};
  final Set<int> _confirmedIds = {};
  bool _isSubmitting = false;
  bool _isDirty = false;
  bool _hasSubmittedSuccessfully = false;
  bool _isHandlingExit = false;
  String? _submitError;

  DateTime get _today {
    final value = widget.today ?? DateTime.now();
    return DateTime(value.year, value.month, value.day);
  }

  @override
  void initState() {
    super.initState();
    _drafts = {
      for (final candidate in widget.result.transactions)
        candidate.candidateId: _BatchRowDraft.fromCandidate(candidate),
    };
    _excludedIds = {
      for (final candidate in widget.result.transactions)
        if (candidate.isExcluded) candidate.candidateId,
    };
    _confirmedIds.addAll(
      widget.result.transactions
          .where((candidate) => candidate.isConfirmed)
          .map((candidate) => candidate.candidateId),
    );
  }

  List<BatchTransaction> get _effectiveCandidates {
    return widget.result.transactions.map((candidate) {
      final edited = _buildCandidate(candidate);
      return edited.copyWith(
        isExcluded: _excludedIds.contains(candidate.candidateId),
        isConfirmed: _confirmedIds.contains(candidate.candidateId),
      );
    }).toList();
  }

  BatchParseResult get _effectiveResult {
    return BatchParseResult(
      originalText: widget.result.originalText,
      transactions: _effectiveCandidates,
    );
  }

  bool get _canSubmit =>
      _effectiveResult.canSubmit &&
      !_isSubmitting &&
      !_hasSubmittedSuccessfully;

  @override
  Widget build(BuildContext context) {
    final result = _effectiveResult;
    final retainedCount = result.retainedTransactions.length;
    return PopScope<Object?>(
      canPop: !_isSubmitting && !_isDirty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          unawaited(_handleExit());
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('批量确认'),
          leading: IconButton(
            key: const Key('batch-back'),
            tooltip: '返回',
            icon: const Icon(Icons.arrow_back),
            onPressed: _handleExit,
          ),
        ),
        body: SafeArea(
          child: CustomScrollView(
            key: const Key('batch-confirm-page'),
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 280),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    Text(
                      '共 ${widget.result.transactions.length} 条候选，保留 $retainedCount 条',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '请逐条核对，错误行修正或移除后再提交。',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 14),
                    ...result.transactions.map(
                      (candidate) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _BatchCandidateCard(
                          key: ValueKey(
                            'batch-candidate-${candidate.candidateId}',
                          ),
                          candidate: candidate,
                          draft: _drafts[candidate.candidateId]!,
                          errorText: _rowErrors[candidate.candidateId],
                          onChanged: (draft) =>
                              _updateDraft(candidate.candidateId, draft),
                          onConfirm: () =>
                              _confirmCandidate(candidate.candidateId),
                          onExclude: () =>
                              _setExcluded(candidate.candidateId, true),
                          onRestore: () =>
                              _setExcluded(candidate.candidateId, false),
                        ),
                      ),
                    ),
                  ]),
                ),
              ),
            ],
          ),
        ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_hasSubmittedSuccessfully)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      '本批账目已提交，不会重复保存。',
                      key: const Key('batch-submit-success'),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  )
                else if (!_canSubmit)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      _submitHint(result),
                      key: const Key('batch-submit-hint'),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                if (_submitError != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      _submitError!,
                      key: const Key('batch-submit-error'),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                FilledButton.icon(
                  key: const Key('batch-confirm-submit'),
                  onPressed: _canSubmit ? _submit : null,
                  icon: _isSubmitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.check),
                  label: Text('确认入库（$retainedCount 条）'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  BatchTransaction _buildCandidate(BatchTransaction candidate) {
    final draft = _drafts[candidate.candidateId]!;
    final originalReviewIssues = candidate.parseResult.issues
        .where((issue) => !issue.isBlocking)
        .toList();
    final issues = <ParseIssue>[...originalReviewIssues];
    final missingFields = <String>[];
    final amountCents = parseYuanToCents(draft.amountText);
    if (amountCents == null) {
      final code = draft.amountText.trim().isEmpty
          ? 'MISSING_AMOUNT'
          : 'INVALID_AMOUNT';
      issues.add(
        ParseIssue(
          code: code,
          field: 'amount_cents',
          message: code == 'MISSING_AMOUNT' ? '请输入金额。' : '金额必须大于 0，且最多保留两位小数。',
        ),
      );
      missingFields.add('amount_cents');
    }

    final type = draft.type;
    if (type == null) {
      issues.add(
        ParseIssue(code: 'TYPE_UNKNOWN', field: 'type', message: '请选择收入或支出。'),
      );
      missingFields.add('type');
    }

    final category = draft.category;
    if (type == null ||
        category == null ||
        !CategoryCatalog.isValidForType(type, category)) {
      issues.add(
        ParseIssue(
          code: 'MISSING_CATEGORY',
          field: 'category',
          message: '请选择与收支匹配的分类。',
        ),
      );
      missingFields.add('category');
    }

    final date = draft.transactionDate.trim();
    final parsedDate = TransactionValidator.parseTransactionDate(date);
    if (parsedDate == null) {
      issues.add(
        ParseIssue(
          code: 'INVALID_DATE',
          field: 'transaction_date',
          message: '请输入有效的 YYYY-MM-DD 日期。',
        ),
      );
      missingFields.add('transaction_date');
    } else if (parsedDate.isAfter(_today)) {
      issues.add(
        ParseIssue(
          code: 'FUTURE_DATE',
          field: 'transaction_date',
          message: '这个日期在未来，请检查日期。',
        ),
      );
    }

    final note = draft.note.trim().isEmpty ? null : draft.note.trim();
    if (note != null && note.length > 200) {
      issues.add(
        ParseIssue(
          code: 'INVALID_NOTE',
          field: 'note',
          message: '备注不能超过 200 个字符。',
        ),
      );
    }

    final editedDraft = TransactionDraft(
      amountCents: amountCents,
      type: type,
      category: category,
      note: note,
      originalText: candidate.draft?.originalText ?? candidate.originalLine,
      transactionDate: date.isEmpty ? null : date,
    );
    final status =
        missingFields.isNotEmpty || issues.any((issue) => issue.isBlocking)
        ? ParseStatus.needsInput
        : issues.isNotEmpty
        ? ParseStatus.needsConfirmation
        : ParseStatus.ready;
    return candidate.copyWith(
      parseResult: ParseResult(
        status: status,
        originalText: candidate.parseResult.originalText,
        draft: editedDraft,
        missingFields: missingFields,
        issues: issues,
      ),
    );
  }

  String _submitHint(BatchParseResult result) {
    if (!result.hasRetainedTransactions) {
      return '请至少保留一条候选。';
    }
    if (result.hasBlockingIssues) {
      return '请修正或移除错误候选。';
    }
    if (result.unconfirmedTransactions.isNotEmpty) {
      return '请先确认带有提示的候选。';
    }
    return '当前批次还不能提交。';
  }

  void _updateDraft(int candidateId, _BatchRowDraft draft) {
    setState(() {
      _drafts[candidateId] = draft;
      _confirmedIds.remove(candidateId);
      _rowErrors[candidateId] = null;
      _isDirty = true;
    });
  }

  void _setExcluded(int candidateId, bool excluded) {
    setState(() {
      if (excluded) {
        _excludedIds.add(candidateId);
      } else {
        _excludedIds.remove(candidateId);
      }
      _rowErrors.remove(candidateId);
      _isDirty = true;
    });
  }

  void _confirmCandidate(int candidateId) {
    final candidate = _effectiveCandidates.firstWhere(
      (item) => item.candidateId == candidateId,
    );
    if (candidate.hasBlockingIssues) {
      setState(() {
        _rowErrors[candidateId] = '请先补全或修正这一行。';
      });
      return;
    }
    setState(() {
      _confirmedIds.add(candidateId);
      _rowErrors[candidateId] = null;
      _isDirty = true;
    });
  }

  Future<void> _submit() async {
    if (!_canSubmit) {
      return;
    }
    final transactions = _effectiveResult.transactionsToSave;
    setState(() {
      _isSubmitting = true;
      _submitError = null;
    });
    try {
      final callback = widget.onConfirm;
      if (callback != null) {
        final saved = await callback(transactions);
        if (!saved && mounted) {
          setState(() {
            _submitError =
                widget.onSubmitFailureMessage?.call() ??
                '批量保存未完成，可能已经写入，请返回列表确认后再操作。';
          });
        } else if (saved && mounted) {
          setState(() {
            _hasSubmittedSuccessfully = true;
            _isDirty = false;
          });
          Navigator.of(context).pop();
        }
      } else if (mounted) {
        setState(() {
          _hasSubmittedSuccessfully = true;
          _isDirty = false;
        });
        Navigator.of(context).pop(transactions);
      }
    } on Exception {
      if (mounted) {
        setState(() {
          _submitError = widget.onSubmitFailureMessage?.call() ?? '批量保存失败，请重试。';
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  Future<void> _handleExit() async {
    if (_isHandlingExit) {
      return;
    }
    if (_isSubmitting) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)
            ?.showSnackBar(const SnackBar(content: Text('正在保存批量账目，请稍候。')));
      }
      return;
    }
    if (!_isDirty) {
      if (mounted) {
        Navigator.of(context).pop();
      }
      return;
    }

    _isHandlingExit = true;
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('放弃批量修改？'),
        content: const Text('已确认、排除或编辑的内容不会保存。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('继续编辑'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('放弃并返回'),
          ),
        ],
      ),
    );
    _isHandlingExit = false;
    if (discard == true && mounted) {
      Navigator.of(context).pop();
    }
  }
}

final class _BatchRowDraft {
  const _BatchRowDraft({
    required this.amountText,
    required this.type,
    required this.category,
    required this.note,
    required this.transactionDate,
  });

  factory _BatchRowDraft.fromCandidate(BatchTransaction candidate) {
    final draft = candidate.draft;
    return _BatchRowDraft(
      amountText: draft?.amountCents == null
          ? ''
          : formatAmountInput(draft!.amountCents!),
      type: draft?.type,
      category: draft?.category,
      note: draft?.note ?? '',
      transactionDate: draft?.transactionDate ?? '',
    );
  }

  final String amountText;
  final TransactionType? type;
  final String? category;
  final String note;
  final String transactionDate;

  _BatchRowDraft copyWith({
    String? amountText,
    TransactionType? type,
    Object? category = _unset,
    String? note,
    String? transactionDate,
  }) {
    return _BatchRowDraft(
      amountText: amountText ?? this.amountText,
      type: type ?? this.type,
      category: identical(category, _unset)
          ? this.category
          : category as String?,
      note: note ?? this.note,
      transactionDate: transactionDate ?? this.transactionDate,
    );
  }
}

class _BatchCandidateCard extends StatefulWidget {
  const _BatchCandidateCard({
    required this.candidate,
    required this.draft,
    required this.errorText,
    required this.onChanged,
    required this.onConfirm,
    required this.onExclude,
    required this.onRestore,
    super.key,
  });

  final BatchTransaction candidate;
  final _BatchRowDraft draft;
  final String? errorText;
  final ValueChanged<_BatchRowDraft> onChanged;
  final VoidCallback onConfirm;
  final VoidCallback onExclude;
  final VoidCallback onRestore;

  @override
  State<_BatchCandidateCard> createState() => _BatchCandidateCardState();
}

class _BatchCandidateCardState extends State<_BatchCandidateCard> {
  late final TextEditingController _amountController;
  late final TextEditingController _noteController;
  late final TextEditingController _dateController;

  @override
  void initState() {
    super.initState();
    _amountController = TextEditingController(text: widget.draft.amountText);
    _noteController = TextEditingController(text: widget.draft.note);
    _dateController = TextEditingController(text: widget.draft.transactionDate);
  }

  @override
  void didUpdateWidget(covariant _BatchCandidateCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncController(_amountController, widget.draft.amountText);
    _syncController(_noteController, widget.draft.note);
    _syncController(_dateController, widget.draft.transactionDate);
  }

  @override
  void dispose() {
    _amountController.dispose();
    _noteController.dispose();
    _dateController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final candidate = widget.candidate;
    if (candidate.isExcluded) {
      return Card(
        key: Key('batch-excluded-${candidate.candidateId}'),
        child: ListTile(
          title: Text('第 ${candidate.candidateId} 条已移除'),
          subtitle: Text(
            candidate.originalLine.trim().isEmpty
                ? '空行'
                : candidate.originalLine,
          ),
          trailing: IconButton(
            key: Key('batch-restore-${candidate.candidateId}'),
            tooltip: '恢复',
            icon: const Icon(Icons.restore),
            onPressed: widget.onRestore,
          ),
        ),
      );
    }

    final options = widget.draft.type == null
        ? const <CategoryDefinition>[]
        : CategoryCatalog.forType(widget.draft.type!);
    return Card(
      key: Key('batch-row-${candidate.candidateId}'),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    '第 ${candidate.candidateId} 条：${candidate.originalLine.trim().isEmpty ? '空行' : candidate.originalLine}',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                IconButton(
                  key: Key('batch-exclude-${candidate.candidateId}'),
                  tooltip: '移除',
                  icon: const Icon(Icons.remove_circle_outline),
                  onPressed: widget.onExclude,
                ),
              ],
            ),
            if (candidate.parseResult.issues.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: candidate.parseResult.issues
                      .map((issue) => Text(issue.message))
                      .toList(),
                ),
              ),
            if (candidate.requiresConfirmation && !candidate.isConfirmed)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: OutlinedButton.icon(
                  key: Key('batch-confirm-row-${candidate.candidateId}'),
                  onPressed: widget.onConfirm,
                  icon: const Icon(Icons.check_circle_outline),
                  label: const Text('确认本行'),
                ),
              )
            else if (candidate.isConfirmed)
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Icon(Icons.check_circle, size: 18),
                    SizedBox(width: 6),
                    Text('本行已确认'),
                  ],
                ),
              ),
            TextFormField(
              key: Key('batch-amount-${candidate.candidateId}'),
              controller: _amountController,
              decoration: const InputDecoration(
                labelText: '金额',
                suffixText: '元',
              ),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              onChanged: (value) =>
                  widget.onChanged(widget.draft.copyWith(amountText: value)),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              children: [
                ChoiceChip(
                  key: Key('batch-type-expense-${candidate.candidateId}'),
                  label: const Text('支出'),
                  selected: widget.draft.type == TransactionType.expense,
                  onSelected: (_) => widget.onChanged(
                    widget.draft.copyWith(
                      type: TransactionType.expense,
                      category: null,
                    ),
                  ),
                ),
                ChoiceChip(
                  key: Key('batch-type-income-${candidate.candidateId}'),
                  label: const Text('收入'),
                  selected: widget.draft.type == TransactionType.income,
                  onSelected: (_) => widget.onChanged(
                    widget.draft.copyWith(
                      type: TransactionType.income,
                      category: null,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (options.isEmpty)
              const Text('请先选择收入或支出')
            else
              DropdownButtonFormField<String>(
                key: Key('batch-category-${candidate.candidateId}'),
                initialValue:
                    options.any(
                      (option) => option.code == widget.draft.category,
                    )
                    ? widget.draft.category
                    : null,
                decoration: const InputDecoration(labelText: '分类'),
                items: options
                    .map(
                      (option) => DropdownMenuItem<String>(
                        value: option.code,
                        child: Text(option.label),
                      ),
                    )
                    .toList(),
                onChanged: (value) =>
                    widget.onChanged(widget.draft.copyWith(category: value)),
              ),
            const SizedBox(height: 10),
            TextFormField(
              key: Key('batch-note-${candidate.candidateId}'),
              controller: _noteController,
              decoration: const InputDecoration(labelText: '备注'),
              maxLength: 200,
              onChanged: (value) =>
                  widget.onChanged(widget.draft.copyWith(note: value)),
            ),
            TextFormField(
              key: Key('batch-date-${candidate.candidateId}'),
              controller: _dateController,
              decoration: const InputDecoration(labelText: '日期'),
              keyboardType: TextInputType.datetime,
              onChanged: (value) => widget.onChanged(
                widget.draft.copyWith(transactionDate: value),
              ),
            ),
            if (widget.errorText != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  widget.errorText!,
                  key: Key('batch-row-error-${candidate.candidateId}'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _syncController(TextEditingController controller, String value) {
    if (controller.text == value) {
      return;
    }
    controller.text = value;
  }
}

final class _Unset {
  const _Unset();
}

const _unset = _Unset();

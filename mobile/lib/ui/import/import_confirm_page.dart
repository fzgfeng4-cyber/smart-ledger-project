import 'dart:async';

import 'package:flutter/material.dart';

import '../../domain/categories/category_catalog.dart';
import '../../domain/import/import_contract.dart';
import '../../domain/models/ledger_transaction.dart';
import '../shared/ledger_formatters.dart';

typedef ImportSubmitCallback = Future<bool> Function(
  ImportDraftBatch updatedBatch,
  List<NewLedgerTransaction> transactions,
);

typedef ImportBatchChangedCallback = void Function(ImportDraftBatch batch);

class ImportConfirmPage extends StatefulWidget {
  const ImportConfirmPage({
    required this.batch,
    required this.onSubmit,
    this.onBatchChanged,
    this.errorMessage,
    this.onRetry,
    this.onBatchRevalidated,
    this.onSubmitFailureMessage,
    this.closeOnSuccess = true,
    super.key,
  });

  final ImportDraftBatch batch;
  final ImportSubmitCallback onSubmit;
  final ImportBatchChangedCallback? onBatchChanged;
  final String? errorMessage;
  final VoidCallback? onRetry;
  final Future<ImportDraftBatch> Function(ImportDraftBatch)? onBatchRevalidated;
  final String? Function()? onSubmitFailureMessage;
  final bool closeOnSuccess;

  @override
  State<ImportConfirmPage> createState() => _ImportConfirmPageState();
}

class _ImportConfirmPageState extends State<ImportConfirmPage> {
  late ImportDraftBatch _batch;
  String? _submitError;
  bool _isSubmitting = false;
  bool _isRevalidating = false;
  bool _isDirty = false;
  bool _hasSubmittedSuccessfully = false;
  bool _isHandlingExit = false;
  int _revalidationRequestId = 0;

  @override
  void initState() {
    super.initState();
    _batch = widget.batch;
  }

  @override
  void didUpdateWidget(covariant ImportConfirmPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.batch, widget.batch)) {
      _batch = widget.batch;
      _submitError = null;
      _isDirty = false;
      _hasSubmittedSuccessfully = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final errorMessage = widget.errorMessage;
    final hasImportCandidates = _batch.candidateRows.isNotEmpty;
    final showSubmitBar =
        errorMessage == null && _batch.rows.isNotEmpty && hasImportCandidates;
    return PopScope<Object?>(
      canPop:
          !_isSubmitting &&
          !_isRevalidating &&
          !_isDirty &&
          !_hasSubmittedSuccessfully,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          unawaited(_handleExit());
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('导入确认'),
          leading: IconButton(
            key: const Key('import-back'),
            tooltip: '返回',
            icon: const Icon(Icons.arrow_back),
            onPressed: _handleExit,
          ),
        ),
        body: SafeArea(
          child: CustomScrollView(
            key: const Key('import-page'),
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            slivers: [
              SliverPadding(
                padding: EdgeInsets.fromLTRB(
                  16,
                  12,
                  16,
                  showSubmitBar ? 112 : 16,
                ),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    _ImportSourceHeader(batch: _batch),
                    const SizedBox(height: 16),
                    if (errorMessage != null) ...[
                      _ImportErrorState(
                        message: errorMessage,
                        onRetry: widget.onRetry,
                      ),
                      const SizedBox(height: 16),
                    ],
                    if (errorMessage == null && _batch.rows.isEmpty)
                      const _ImportEmptyState()
                    else ...[
                      _ImportSummary(batch: _batch),
                      const SizedBox(height: 16),
                      ..._batch.rows.map(
                        (row) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _ImportRowCard(
                            key: ValueKey(
                              'import-row-${row.rawRow.lineNumber}',
                            ),
                            row: row,
                            onConfirm: _isSubmitting || _isRevalidating
                                ? null
                                : row.hasBlockingIssues
                                ? null
                                : () => _confirmRow(row.rawRow.lineNumber),
                            onExclude: _isSubmitting || _isRevalidating
                                ? null
                                : () => _excludeRow(row.rawRow.lineNumber),
                            onRestore: _isSubmitting || _isRevalidating
                                ? null
                                : () => _restoreRow(row.rawRow.lineNumber),
                            onCategoryChanged: _isSubmitting || _isRevalidating
                                ? null
                                : (code) => unawaited(
                                    _changeCategory(
                                      row.rawRow.lineNumber,
                                      code,
                                    ),
                                  ),
                          ),
                        ),
                      ),
                    ],
                    if (_submitError != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        _submitError!,
                        key: const Key('import-submit-error'),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                  ]),
                ),
              ),
            ],
          ),
        ),
        bottomNavigationBar: showSubmitBar
            ? SafeArea(
                top: false,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    border: Border(
                      top: BorderSide(
                        color: Theme.of(context).colorScheme.outlineVariant,
                      ),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    child: SizedBox(
                      height: 48,
                      width: double.infinity,
                      child: FilledButton.icon(
                        key: const Key('import-submit'),
                        onPressed: _canSubmit ? _submit : null,
                        icon: _isSubmitting
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.check),
                        label: Text(
                          '确认导入（${_batch.transactionsToSave.length} 条）',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ),
                ),
              )
            : null,
      ),
    );
  }

  bool get _canSubmit {
    return !_isSubmitting && !_isRevalidating && _batch.canSubmit;
  }

  void _confirmRow(int lineNumber) {
    final updated = _batch.confirm(lineNumber);
    _applyBatch(updated);
  }

  void _excludeRow(int lineNumber) {
    final updated = _batch.exclude(lineNumber);
    _applyBatch(updated);
  }

  void _restoreRow(int lineNumber) {
    final updated = _batch.restore(lineNumber);
    _applyBatch(updated);
  }

  Future<void> _changeCategory(int lineNumber, String? categoryCode) async {
    final row = _batch.findByLineNumber(lineNumber);
    if (row == null || categoryCode == null || categoryCode.isEmpty) {
      return;
    }

    final updatedSuggestions = <ImportCategorySuggestion>[
      ImportCategorySuggestion(
        categoryCode: categoryCode,
        reason: _suggestionReason(row, categoryCode),
      ),
      for (final suggestion in row.categorySuggestions)
        if (suggestion.categoryCode != categoryCode) suggestion,
    ];
    final updatedRow = row.copyWith(
      categorySuggestions: updatedSuggestions,
      reviewState: ImportReviewState.pending,
    );
    final updatedBatch = _batch.updateRow(updatedRow);
    _applyBatch(updatedBatch);

    final revalidate = widget.onBatchRevalidated;
    if (revalidate == null) {
      return;
    }
    final requestId = ++_revalidationRequestId;
    setState(() {
      _isRevalidating = true;
    });
    try {
      final revalidated = await revalidate(updatedBatch);
      if (mounted && requestId == _revalidationRequestId) {
        _applyBatch(revalidated);
      }
    } catch (_) {
      if (mounted && requestId == _revalidationRequestId) {
        setState(() {
          _submitError = '重复检查失败，请重试后再提交。';
        });
      }
    } finally {
      if (mounted && requestId == _revalidationRequestId) {
        setState(() {
          _isRevalidating = false;
        });
      }
    }
  }

  void _applyBatch(ImportDraftBatch updatedBatch) {
    setState(() {
      _batch = updatedBatch;
      _submitError = null;
      _isDirty = true;
    });
    widget.onBatchChanged?.call(updatedBatch);
  }

  Future<void> _submit() async {
    if (_hasSubmittedSuccessfully) {
      return;
    }
    final transactions = _batch.transactionsToSave;
    if (!_batch.canSubmit || transactions.isEmpty) {
      return;
    }

    setState(() {
      _isSubmitting = true;
      _submitError = null;
    });

    try {
      final success = await widget.onSubmit(_batch, transactions);
      if (!mounted) {
        return;
      }
      if (success && widget.closeOnSuccess) {
        setState(() {
          _hasSubmittedSuccessfully = true;
          _isDirty = false;
        });
        Navigator.of(context).pop(transactions);
      } else if (!success) {
        setState(() {
          _submitError =
              widget.onSubmitFailureMessage?.call() ??
              '批量保存未完成，可能已经写入，请返回列表确认后再操作。';
        });
      } else if (success) {
        setState(() {
          _hasSubmittedSuccessfully = true;
          _isDirty = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _submitError =
              widget.onSubmitFailureMessage?.call() ??
              '批量保存未完成，可能已经写入，请返回列表确认后再操作。';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  Future<void> _handleExit() async {
    if (_isHandlingExit) {
      return;
    }
    if (_isSubmitting || _isRevalidating) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)
            ?.showSnackBar(const SnackBar(content: Text('正在处理导入，请稍候。')));
      }
      return;
    }
    if (!_isDirty || _hasSubmittedSuccessfully) {
      if (mounted) {
        Navigator.of(context).pop();
      }
      return;
    }

    _isHandlingExit = true;
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('放弃导入修改？'),
        content: const Text('已确认、排除或修改分类的内容不会保存。'),
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

  String? _suggestionReason(ImportDraftRow row, String categoryCode) {
    for (final suggestion in row.categorySuggestions) {
      if (suggestion.categoryCode == categoryCode) {
        return suggestion.reason;
      }
    }
    return '现有分类规则建议 ${CategoryCatalog.findByCode(categoryCode)?.label ?? categoryCode}。';
  }
}

class _ImportSourceHeader extends StatelessWidget {
  const _ImportSourceHeader({required this.batch});

  final ImportDraftBatch batch;

  @override
  Widget build(BuildContext context) {
    final fileName = batch.source.fileName;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '导入来源',
          style: Theme.of(context).textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        Text(
          fileName,
          key: const Key('import-source-file-name'),
          style: Theme.of(context).textTheme.titleLarge
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Text(
          _sourceTypeLabel(batch.source.type),
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ],
    );
  }
}

class _ImportSummary extends StatelessWidget {
  const _ImportSummary({required this.batch});

  final ImportDraftBatch batch;

  @override
  Widget build(BuildContext context) {
    final retainedCount = batch.retainedRows.length;
    final candidateCount = batch.candidateRows.length;
    final excludedCount = batch.excludedRows.length;
    final blockingCount = batch.blockingRows.length;
    final duplicateCount = batch.rows
        .where((row) => row.duplicateNotice != null)
        .length;
    final confirmationCount = batch.candidateRows
        .where((row) => row.reviewState == ImportReviewState.pending)
        .length;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            _SummaryItem(
              label: '保留',
              value: '$retainedCount',
              valueKey: const Key('import-count-retained-value'),
            ),
            _SummaryItem(
              label: '候选',
              value: '$candidateCount',
              valueKey: const Key('import-count-candidate-value'),
            ),
            _SummaryItem(
              label: '排除',
              value: '$excludedCount',
              valueKey: const Key('import-count-excluded-value'),
            ),
            _SummaryItem(
              label: '阻塞',
              value: '$blockingCount',
              valueKey: const Key('import-count-blocking-value'),
            ),
            _SummaryItem(
              label: '待确认',
              value: '$confirmationCount',
              valueKey: const Key('import-count-confirmation-value'),
            ),
            _SummaryItem(
              label: '重复提示',
              value: '$duplicateCount',
              valueKey: const Key('import-count-duplicate-value'),
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryItem extends StatelessWidget {
  const _SummaryItem({
    required this.label,
    required this.value,
    required this.valueKey,
  });

  final String label;
  final String value;
  final Key valueKey;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 4),
        Text(
          '$value 条',
          key: valueKey,
          style: Theme.of(context).textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}

class _ImportRowCard extends StatelessWidget {
  const _ImportRowCard({
    required this.row,
    required this.onConfirm,
    required this.onExclude,
    required this.onRestore,
    required this.onCategoryChanged,
    super.key,
  });

  final ImportDraftRow row;
  final VoidCallback? onConfirm;
  final VoidCallback? onExclude;
  final VoidCallback? onRestore;
  final ValueChanged<String?>? onCategoryChanged;

  @override
  Widget build(BuildContext context) {
    if (row.isExcluded) {
      return Card(
        key: Key('import-excluded-${row.rawRow.lineNumber}'),
        margin: EdgeInsets.zero,
        child: ListTile(
          title: Text(
            '第 ${row.rawRow.lineNumber} 行已排除',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          subtitle: Text(
            row.rawRow.rawText.trim().isEmpty ? '空行' : row.rawRow.rawText,
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: SizedBox(
            height: 48,
            child: TextButton.icon(
              key: Key('import-restore-row-${row.rawRow.lineNumber}'),
              onPressed: onRestore,
              icon: const Icon(Icons.restore),
              label: const Text('恢复'),
            ),
          ),
        ),
      );
    }

    final categoryOptions = row.categorySuggestions;
    final selectedCategory = row.suggestedCategoryCode;
    final categoryLabel = selectedCategory == null
        ? '暂无分类建议'
        : categoryName(selectedCategory);
    final typeLabel = row.transactionType == null
        ? '未识别'
        : transactionTypeLabel(row.transactionType!);
    final amountLabel = row.amountCents == null
        ? '金额待确认'
        : formatMoneyCents(row.amountCents!);

    return Card(
      key: Key('import-row-${row.rawRow.lineNumber}'),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final confirmButton = OutlinedButton.icon(
                  key: Key('import-confirm-row-${row.rawRow.lineNumber}'),
                  onPressed: onConfirm,
                  icon: const Icon(Icons.check_circle_outline),
                  label: const Text('确认本行'),
                );
                final excludeButton = OutlinedButton.icon(
                  key: Key('import-exclude-row-${row.rawRow.lineNumber}'),
                  onPressed: onExclude,
                  icon: const Icon(Icons.remove_circle_outline),
                  label: const Text('排除'),
                );

                if (constraints.maxWidth < 420) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        '第 ${row.rawRow.lineNumber} 行',
                        style: Theme.of(context).textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(height: 48, child: confirmButton),
                      const SizedBox(height: 8),
                      SizedBox(height: 48, child: excludeButton),
                    ],
                  );
                }

                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        '第 ${row.rawRow.lineNumber} 行',
                        style: Theme.of(context).textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                    SizedBox(width: 136, height: 48, child: confirmButton),
                    const SizedBox(width: 8),
                    SizedBox(width: 104, height: 48, child: excludeButton),
                  ],
                );
              },
            ),
            const SizedBox(height: 8),
            Text(
              row.rawRow.rawText.trim().isEmpty ? '空行' : row.rawRow.rawText,
              key: Key('import-row-raw-${row.rawRow.lineNumber}'),
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
            ),
            if (row.duplicateNotice != null) ...[
              const SizedBox(height: 12),
              DecoratedBox(
                key: Key('import-row-duplicate-${row.rawRow.lineNumber}'),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.tertiaryContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    row.duplicateNotice!.message,
                    key: Key(
                      'import-row-duplicate-message-${row.rawRow.lineNumber}',
                    ),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _MetaChip(label: row.transactionDate ?? '日期待确认'),
                _MetaChip(label: amountLabel),
                _MetaChip(label: typeLabel),
                _MetaChip(label: categoryLabel),
              ],
            ),
            if (row.hasBlockingIssues) ...[
              const SizedBox(height: 12),
              DecoratedBox(
                key: Key('import-row-blocking-${row.rawRow.lineNumber}'),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '需要修正',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onErrorContainer,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      for (final issue in row.issues.where(
                        (issue) => issue.isBlocking,
                      ))
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text(issue.message),
                        ),
                    ],
                  ),
                ),
              ),
            ],
            if (categoryOptions.isNotEmpty) ...[
              const SizedBox(height: 12),
              InputDecorator(
                decoration: const InputDecoration(
                  labelText: '分类建议',
                  filled: true,
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    key: Key('import-category-${row.rawRow.lineNumber}'),
                    isExpanded: true,
                    value: selectedCategory,
                    items: categoryOptions
                        .map(
                          (suggestion) => DropdownMenuItem<String>(
                            value: suggestion.categoryCode,
                            child: Text(categoryName(suggestion.categoryCode)),
                          ),
                        )
                        .toList(growable: false),
                    onChanged: onCategoryChanged,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Text(label),
      ),
    );
  }
}

class _ImportEmptyState extends StatelessWidget {
  const _ImportEmptyState();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      key: const Key('import-empty-state'),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Padding(
        padding: EdgeInsets.all(16),
        child: Text('没有可导入的账单内容。'),
      ),
    );
  }
}

class _ImportErrorState extends StatelessWidget {
  const _ImportErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      key: const Key('import-error-state'),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(message),
            if (onRetry != null) ...[
              const SizedBox(height: 8),
              TextButton.icon(
                key: const Key('import-retry'),
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('重试'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

String _sourceTypeLabel(ImportSourceType type) {
  return switch (type) {
    ImportSourceType.wechatCsv => '微信 CSV 导入',
    ImportSourceType.alipayCsv => '支付宝 CSV 导入',
    ImportSourceType.otherCsv => '其他 CSV 导入',
    ImportSourceType.unknown => '未知来源',
  };
}

String categoryName(String categoryCode) {
  return CategoryCatalog.findByCode(categoryCode)?.label ?? categoryCode;
}

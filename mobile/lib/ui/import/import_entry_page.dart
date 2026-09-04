import 'package:flutter/material.dart';

import '../../data/import/import_coordinator.dart';
import '../../data/import/import_file_picker.dart';
import '../../domain/import/import_contract.dart';
import '../../domain/models/ledger_transaction.dart';
import 'import_confirm_page.dart';

class ImportEntryPage extends StatefulWidget {
  const ImportEntryPage({
    required this.coordinator,
    this.onBatchSaved,
    this.onSaveBatch,
    this.onBatchSaveFailureMessage,
    super.key,
  });

  final ImportCoordinator coordinator;
  final Future<void> Function()? onBatchSaved;
  final Future<bool> Function(
    ImportDraftBatch batch,
    List<NewLedgerTransaction> transactions,
  )?
  onSaveBatch;
  final String? Function()? onBatchSaveFailureMessage;

  @override
  State<ImportEntryPage> createState() => _ImportEntryPageState();
}

class _ImportEntryPageState extends State<ImportEntryPage> {
  var _source = ImportSourceType.wechatCsv;
  var _isPicking = false;
  String? _errorMessage;
  String? _statusMessage;
  String? _importSaveFailureMessage;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const Key('import-entry-page'),
      appBar: AppBar(
        title: const Text('导入账单'),
        leading: IconButton(
          key: const Key('import-entry-back'),
          tooltip: '返回',
          icon: const Icon(Icons.arrow_back),
          onPressed: _isPicking ? null : () => Navigator.of(context).maybePop(),
        ),
      ),
      body: SafeArea(
        child: CustomScrollView(
          key: const Key('import-entry-scroll'),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  Text(
                    '账单来源',
                    style: Theme.of(context).textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 10),
                  SegmentedButton<ImportSourceType>(
                    key: const Key('import-source-selector'),
                    segments: const [
                      ButtonSegment<ImportSourceType>(
                        value: ImportSourceType.wechatCsv,
                        label: Text('微信账单'),
                        icon: Icon(Icons.chat_bubble_outline),
                      ),
                      ButtonSegment<ImportSourceType>(
                        value: ImportSourceType.alipayCsv,
                        label: Text('支付宝账单'),
                        icon: Icon(Icons.account_balance_wallet_outlined),
                      ),
                    ],
                    selected: {_source},
                    onSelectionChanged: _isPicking
                        ? null
                        : (selection) {
                            if (selection.isEmpty) {
                              return;
                            }
                            setState(() {
                              _source = selection.first;
                              _errorMessage = null;
                              _statusMessage = null;
                              _importSaveFailureMessage = null;
                            });
                          },
                    showSelectedIcon: false,
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    key: const Key('import-pick-file'),
                    onPressed: _isPicking ? null : _pickAndOpen,
                    icon: _isPicking
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.file_open),
                    label: Text(_isPicking ? '读取中...' : '选择 CSV 文件'),
                  ),
                  if (_errorMessage != null) ...[
                    const SizedBox(height: 16),
                    _ImportEntryError(
                      message: _errorMessage!,
                      onRetry: _isPicking ? null : _pickAndOpen,
                    ),
                  ],
                  if (_statusMessage != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      _statusMessage!,
                      key: const Key('import-entry-status'),
                    ),
                  ],
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickAndOpen() async {
    if (_isPicking) {
      return;
    }

    setState(() {
      _isPicking = true;
      _errorMessage = null;
      _statusMessage = null;
      _importSaveFailureMessage = null;
    });

    try {
      final batch = await widget.coordinator.pickAndParse(_source);
      if (!mounted) {
        return;
      }
      if (batch == null) {
        setState(() {
          _statusMessage = '已取消选择，账本未修改。';
        });
        return;
      }

      setState(() {
        _isPicking = false;
      });
      final result = await Navigator.of(context)
          .push<List<NewLedgerTransaction>>(
            MaterialPageRoute<List<NewLedgerTransaction>>(
              builder: (_) => ImportConfirmRoute(
                batch: batch,
                onSubmit: _saveBatch,
                onBatchRevalidated: widget.coordinator.recheckDuplicates,
                onSubmitFailureMessage: () =>
                    _importSaveFailureMessage ?? '导入保存失败，账本未修改，请重试。',
              ),
            ),
          );
      if (!mounted) {
        return;
      }
      setState(() {
        _statusMessage = result == null
            ? '已取消导入确认，账本未修改。'
            : '导入已保存 ${result.length} 条账目。';
      });
    } on ImportCoordinatorException catch (error) {
      if (mounted) {
        setState(() {
          _errorMessage = error.message;
        });
      }
    } on ImportFilePickerException catch (error) {
      if (mounted) {
        setState(() {
          _errorMessage = error.message;
        });
      }
    } on Object catch (_) {
      if (mounted) {
        setState(() {
          _errorMessage = '导入文件失败，请重试。';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isPicking = false;
        });
      }
    }
  }

  Future<bool> _saveBatch(
    ImportDraftBatch batch,
    List<NewLedgerTransaction> transactions,
  ) async {
    _importSaveFailureMessage = null;
    final saveBatch = widget.onSaveBatch;
    if (saveBatch != null) {
      try {
        final saved = await saveBatch(batch, transactions);
        if (!saved) {
          _importSaveFailureMessage = '导入保存失败，账本未修改，请重试。';
        }
        return saved;
      } on Object catch (error) {
        _importSaveFailureMessage = _formatImportSaveFailure(error);
        return false;
      }
    }

    try {
      await widget.coordinator.saveBatch(batch, transactions);
    } on Object catch (error) {
      _importSaveFailureMessage = _formatImportSaveFailure(error);
      return false;
    }

    try {
      await widget.onBatchSaved?.call();
    } on Object {
      // 数据库已经成功写入，界面刷新失败不应改写保存结果。
    }
    return true;
  }

  String _formatImportSaveFailure(Object error) {
    if (error is ImportCoordinatorException) {
      return error.message;
    }
    return '导入保存失败，账本未修改，请重试。';
  }
}

class ImportConfirmRoute extends StatefulWidget {
  const ImportConfirmRoute({
    required this.batch,
    required this.onSubmit,
    this.onBatchRevalidated,
    this.onSubmitFailureMessage,
    super.key,
  });

  final ImportDraftBatch batch;
  final ImportSubmitCallback onSubmit;
  final Future<ImportDraftBatch> Function(ImportDraftBatch)? onBatchRevalidated;
  final String? Function()? onSubmitFailureMessage;

  @override
  State<ImportConfirmRoute> createState() => _ImportConfirmRouteState();
}

class _ImportConfirmRouteState extends State<ImportConfirmRoute> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _showDuplicateNotice();
    });
  }

  @override
  Widget build(BuildContext context) {
    return ImportConfirmPage(
      batch: widget.batch,
      onSubmit: widget.onSubmit,
      onBatchRevalidated: widget.onBatchRevalidated,
      onSubmitFailureMessage: widget.onSubmitFailureMessage,
    );
  }

  void _showDuplicateNotice() {
    if (!mounted) {
      return;
    }
    final duplicateRows = widget.batch.rows
        .where((row) => row.duplicateNotice != null)
        .toList(growable: false);
    if (duplicateRows.isEmpty) {
      return;
    }

    final firstNotice = duplicateRows.first.duplicateNotice;
    final detail = firstNotice == null ? '' : ' ${firstNotice.message}';
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        key: const Key('import-duplicate-snackbar'),
        duration: const Duration(seconds: 12),
        content: Text(
          '发现 ${duplicateRows.length} 条疑似重复账目。$detail',
          key: const Key('import-duplicate-notice'),
        ),
      ),
    );
  }
}

class _ImportEntryError extends StatelessWidget {
  const _ImportEntryError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      key: const Key('import-entry-error'),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(message),
            const SizedBox(height: 8),
            TextButton.icon(
              key: const Key('import-entry-retry'),
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }
}

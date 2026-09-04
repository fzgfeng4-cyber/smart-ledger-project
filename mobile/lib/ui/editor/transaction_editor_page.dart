import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../domain/models/transaction_type.dart';
import '../ledger_ui_controller.dart';
import '../models/ledger_ui_models.dart';
import '../shared/ledger_formatters.dart';

class TransactionEditorPage extends StatelessWidget {
  const TransactionEditorPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<LedgerUiController>(
      builder: (context, controller, _) {
        return PopScope<Object?>(
          canPop: !controller.isBusy && !controller.hasUnsavedDraft,
          onPopInvokedWithResult: (didPop, _) async {
            if (didPop || controller.isBusy) {
              return;
            }
            await _confirmDiscardAndPop(context, controller);
          },
          child: _EditorScaffold(controller: controller),
        );
      },
    );
  }
}

class _EditorScaffold extends StatelessWidget {
  const _EditorScaffold({required this.controller});

  final LedgerUiController controller;

  @override
  Widget build(BuildContext context) {
    final draft = controller.draft;
    final isBusy = controller.isBusy;
    if (draft == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('账目')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              controller.editorErrorMessage ?? '没有正在编辑的账目',
              key: const Key('editor-operation-result'),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    final validationMessage = controller.validationMessage;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          key: const Key('editor-back'),
          tooltip: '返回',
          onPressed: isBusy
              ? null
              : () => _confirmDiscardAndPop(context, controller),
          icon: const Icon(Icons.arrow_back),
        ),
        title: Text(draft.mode == EditorMode.edit ? '编辑账目' : '新增账目'),
      ),
      body: SafeArea(
        child: IgnorePointer(
          ignoring: isBusy,
          child: CustomScrollView(
            key: const Key('editor-page'),
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 240),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    _OriginalTextPanel(draft: draft),
                    const SizedBox(height: 14),
                    _IssuePanel(draft: draft),
                    _MoneyField(draft: draft, enabled: !isBusy),
                    const SizedBox(height: 12),
                    _TypeField(draft: draft, enabled: !isBusy),
                    const SizedBox(height: 12),
                    _CategoryField(draft: draft, enabled: !isBusy),
                    const SizedBox(height: 12),
                    _NoteField(draft: draft, enabled: !isBusy),
                    const SizedBox(height: 12),
                    _DateField(
                      draft: draft,
                      today: controller.today,
                      enabled: !isBusy,
                    ),
                    if (draft.mode == EditorMode.edit) ...[
                      const SizedBox(height: 24),
                      OutlinedButton.icon(
                        key: const Key('delete-entry-button'),
                        onPressed: isBusy
                            ? null
                            : () async {
                                final confirmed = await _showDeleteDialog(
                                  context,
                                  controller,
                                );
                                if (!confirmed || !context.mounted) {
                                  return;
                                }
                                await _waitForEditorRouteToBecomeCurrent(
                                  context,
                                );
                                if (!context.mounted) {
                                  return;
                                }
                                final deleted =
                                    await controller.deleteCurrentEntry();
                                if (deleted && context.mounted) {
                                  Navigator.of(context).pop();
                                }
                              },
                        icon: const Icon(Icons.delete_outline),
                        label: const Text('删除账目'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor:
                              Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                  ]),
                ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (validationMessage != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    validationMessage,
                    key: const Key('editor-validation-message'),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              if (controller.editorErrorMessage != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    controller.editorErrorMessage!,
                    key: const Key('editor-error-message'),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              FilledButton.icon(
                key: const Key('editor-save'),
                onPressed: !isBusy && controller.canSaveDraft
                    ? () async {
                        final saved = await controller.saveDraft();
                        if (saved) {
                          if (context.mounted) {
                            Navigator.of(context).pop();
                          }
                        }
                      }
                    : null,
                icon: const Icon(Icons.check),
                label: Text(draft.mode == EditorMode.edit ? '保存修改' : '确认记账'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OriginalTextPanel extends StatelessWidget {
  const _OriginalTextPanel({required this.draft});

  final EditorDraft draft;

  @override
  Widget build(BuildContext context) {
    final title = draft.mode == EditorMode.edit ? '最初输入' : '原始输入';
    final text = draft.originalText.trim().isEmpty
        ? '手动新建'
        : draft.originalText;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 6),
            SelectableText(text, key: const Key('original-text-readonly')),
          ],
        ),
      ),
    );
  }
}

class _IssuePanel extends StatelessWidget {
  const _IssuePanel({required this.draft});

  final EditorDraft draft;

  @override
  Widget build(BuildContext context) {
    final issues = draft.unresolvedIssues;
    if (issues.isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: DecoratedBox(
        key: const Key('issue-panel'),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.tertiaryContainer,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.info_outline),
                  const SizedBox(width: 8),
                  Text(
                    '需要确认',
                    style: Theme.of(context).textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ...issues.map((issue) => _IssueItem(issue: issue)),
            ],
          ),
        ),
      ),
    );
  }
}

class _IssueItem extends StatelessWidget {
  const _IssueItem({required this.issue});

  final UiIssue issue;

  @override
  Widget build(BuildContext context) {
    final controller = context.read<LedgerUiController>();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(issue.message),
          const SizedBox(height: 8),
          if (issue.code == 'BARE_AMOUNT')
            TextButton.icon(
              key: const Key('acknowledge-amount'),
              onPressed: () => controller.acknowledgeIssue(issue.code),
              icon: const Icon(Icons.check_circle_outline),
              label: const Text('已核对金额'),
            ),
          if (issue.code == 'CATEGORY_CONFLICT')
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.tonalIcon(
                  key: const Key('keep-dining'),
                  onPressed: () => controller.updateCategory('dining'),
                  icon: const Icon(Icons.restaurant),
                  label: const Text('保留餐饮'),
                ),
                OutlinedButton.icon(
                  key: const Key('change-to-children'),
                  onPressed: () => controller.updateCategory('children'),
                  icon: const Icon(Icons.child_care),
                  label: const Text('改为孩子'),
                ),
              ],
            ),
          if (issue.code == 'CATEGORY_FALLBACK')
            TextButton.icon(
              key: const Key('acknowledge-category'),
              onPressed: () => controller.acknowledgeIssue(issue.code),
              icon: const Icon(Icons.check_circle_outline),
              label: const Text('确认当前分类'),
            ),
          if (issue.code == 'LOCAL_CLASSIFICATION_SUGGESTION')
            TextButton.icon(
              key: const Key('acknowledge-local-classification'),
              onPressed: () => controller.acknowledgeIssue(issue.code),
              icon: const Icon(Icons.check_circle_outline),
              label: const Text('确认本地分类建议'),
            ),
          if (issue.code == 'MULTIPLE_AMOUNTS')
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  key: const Key('rewrite-original-text'),
                  onPressed: () =>
                      _confirmDiscardAndPop(context, controller, force: true),
                  icon: const Icon(Icons.edit),
                  label: const Text('返回修改原句'),
                ),
                OutlinedButton.icon(
                  key: const Key('split-manually'),
                  onPressed: () {
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(const SnackBar(content: Text('请分别输入两笔账。')));
                  },
                  icon: const Icon(Icons.call_split),
                  label: const Text('分别输入两笔'),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _MoneyField extends StatelessWidget {
  const _MoneyField({required this.draft, required this.enabled});

  final EditorDraft draft;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final controller = context.read<LedgerUiController>();
    return TextFormField(
      key: const Key('editor-amount-field'),
      enabled: enabled,
      initialValue: draft.amountText,
      decoration: const InputDecoration(
        labelText: '金额',
        suffixText: '元',
        filled: true,
      ),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      onChanged: controller.updateAmountText,
    );
  }
}

class _TypeField extends StatelessWidget {
  const _TypeField({required this.draft, required this.enabled});

  final EditorDraft draft;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final controller = context.read<LedgerUiController>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('收入 / 支出', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            ChoiceChip(
              key: const Key('type-expense'),
              label: const Text('支出'),
              avatar: const Icon(Icons.arrow_upward),
              selected: draft.type == TransactionType.expense,
              onSelected: enabled
                  ? (_) => controller.updateType(TransactionType.expense)
                  : null,
            ),
            ChoiceChip(
              key: const Key('type-income'),
              label: const Text('收入'),
              avatar: const Icon(Icons.arrow_downward),
              selected: draft.type == TransactionType.income,
              onSelected: enabled
                  ? (_) => controller.updateType(TransactionType.income)
                  : null,
            ),
          ],
        ),
      ],
    );
  }
}

class _CategoryField extends StatelessWidget {
  const _CategoryField({required this.draft, required this.enabled});

  final EditorDraft draft;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<LedgerUiController>();
    final options = controller.categoryOptions;
    return Column(
      key: const Key('category-field'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('分类', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 8),
        if (options.isEmpty)
          const Text('请先选择收入或支出')
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: options
                .map(
                  (category) => ChoiceChip(
                    key: Key('category-${category.code}'),
                    label: Text(category.label),
                    selected: draft.category == category.code,
                    onSelected: enabled
                        ? (_) => controller.updateCategory(category.code)
                        : null,
                  ),
                )
                .toList(),
          ),
      ],
    );
  }
}

class _NoteField extends StatelessWidget {
  const _NoteField({required this.draft, required this.enabled});

  final EditorDraft draft;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final controller = context.read<LedgerUiController>();
    return TextFormField(
      key: const Key('editor-note-field'),
      initialValue: draft.note,
      enabled: enabled,
      decoration: const InputDecoration(
        labelText: '备注',
        hintText: '未填写',
        filled: true,
      ),
      maxLength: 200,
      onChanged: controller.updateNote,
    );
  }
}

class _DateField extends StatelessWidget {
  const _DateField({
    required this.draft,
    required this.today,
    required this.enabled,
  });

  final EditorDraft draft;
  final DateTime today;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final controller = context.read<LedgerUiController>();
    final isFuture = isFutureDate(draft.transactionDate, today);
    return TextFormField(
      key: const Key('editor-date-field'),
      initialValue: draft.transactionDate,
      enabled: enabled,
      decoration: InputDecoration(
        labelText: '日期',
        helperText: formatDateLabel(draft.transactionDate, today),
        errorText: isFuture ? '这个日期在未来，请检查日期。' : null,
        filled: true,
      ),
      keyboardType: TextInputType.datetime,
      onChanged: controller.updateDate,
    );
  }
}

Future<void> _confirmDiscardAndPop(
  BuildContext context,
  LedgerUiController controller, {
  bool force = false,
}) async {
  if (controller.isBusy) {
    return;
  }
  if (!controller.hasUnsavedDraft || force) {
    controller.discardEditorChanges();
    if (context.mounted) {
      Navigator.of(context).pop();
    }
    return;
  }

  final shouldDiscard = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      key: const Key('discard-dialog'),
      title: const Text('放弃更改？'),
      content: const Text('这笔账还没有保存。'),
      actions: [
        TextButton(
          key: const Key('continue-editing'),
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('继续编辑'),
        ),
        FilledButton(
          key: const Key('discard-changes'),
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('放弃更改'),
        ),
      ],
    ),
  );

  if (shouldDiscard == true && context.mounted) {
    controller.discardEditorChanges();
    Navigator.of(context).pop();
  }
}

Future<bool> _showDeleteDialog(
  BuildContext context,
  LedgerUiController controller,
) {
  final draft = controller.draft;
  if (draft == null) {
    return Future.value(false);
  }

  return showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      key: const Key('delete-confirmation-dialog'),
      title: const Text('确定删除这笔账吗？'),
      content: Text(
        '${transactionTypeLabel(draft.type)}  '
        '${draft.amountText.isEmpty ? '待填写' : '¥${draft.amountText}'}  '
        '${categoryLabel(draft.category)}  '
        '${draft.note.trim().isEmpty ? '未填写' : draft.note.trim()}',
      ),
      actions: [
        TextButton(
          key: const Key('cancel-delete'),
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('取消'),
        ),
        FilledButton.icon(
          key: const Key('confirm-delete'),
          onPressed: () => Navigator.of(dialogContext).pop(true),
          icon: const Icon(Icons.delete_outline),
          label: const Text('删除账目'),
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(dialogContext).colorScheme.error,
            foregroundColor: Theme.of(dialogContext).colorScheme.onError,
          ),
        ),
      ],
    ),
  ).then((confirmed) => confirmed ?? false);
}

Future<void> _waitForEditorRouteToBecomeCurrent(BuildContext context) async {
  final route = ModalRoute.of(context);
  if (route == null || route.isCurrent) {
    return;
  }

  for (var attempt = 0; attempt < 10; attempt += 1) {
    await WidgetsBinding.instance.endOfFrame;
    if (route.isCurrent) {
      return;
    }
  }
}

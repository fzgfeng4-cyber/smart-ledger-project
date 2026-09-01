import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/backup/backup_service.dart';
import '../../domain/models/transaction_type.dart';
import '../ledger_ui_controller.dart';
import '../models/ledger_ui_models.dart';
import 'ledger_formatters.dart';

class AppTopBar extends StatelessWidget {
  const AppTopBar({required this.title, this.trailing, super.key});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: Theme.of(context).textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        ..._present(trailing),
        const BackupMenuButton(),
      ],
    );
  }
}

class BackupMenuButton extends StatelessWidget {
  const BackupMenuButton({super.key});

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      key: const Key('backup-menu'),
      tooltip: '更多',
      icon: const Icon(Icons.more_vert),
      onSelected: (value) {
        unawaited(_handleBackupSelection(context, value));
      },
      itemBuilder: (context) => const [
        PopupMenuItem(
          key: Key('backup-export-action'),
          value: 'backup',
          child: ListTile(
            leading: Icon(Icons.ios_share),
            title: Text('备份数据'),
            subtitle: Text('保存一份本地 JSON 备份'),
          ),
        ),
        PopupMenuItem(
          key: Key('backup-restore-action'),
          value: 'restore',
          child: ListTile(
            leading: Icon(Icons.restore),
            title: Text('恢复备份'),
            subtitle: Text('从本地备份恢复账目'),
          ),
        ),
      ],
    );
  }
}

class StatCard extends StatelessWidget {
  const StatCard({
    required this.label,
    required this.amountCents,
    required this.icon,
    super.key,
  });

  final String label;
  final int amountCents;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: colorScheme.primary),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    label,
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                formatMoneyCents(amountCents),
                style: Theme.of(context).textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class TransactionTile extends StatelessWidget {
  const TransactionTile({
    required this.entry,
    required this.today,
    required this.onTap,
    super.key,
  });

  final UiLedgerEntry entry;
  final DateTime today;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isIncome = entry.type == TransactionType.income;
    final colorScheme = Theme.of(context).colorScheme;
    final typeColor = isIncome ? colorScheme.primary : colorScheme.error;
    final note = entry.note == null || entry.note!.trim().isEmpty
        ? '未填写'
        : entry.note!;

    return ListTile(
      key: Key('transaction-${entry.id}'),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      tileColor: colorScheme.surfaceContainerLow,
      leading: CircleAvatar(
        backgroundColor: typeColor.withValues(alpha: 0.12),
        foregroundColor: typeColor,
        child: Icon(isIncome ? Icons.arrow_downward : Icons.arrow_upward),
      ),
      title: Row(
        children: [
          Text(
            transactionTypeLabel(entry.type),
            style: TextStyle(color: typeColor, fontWeight: FontWeight.w700),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              formatMoneyCents(entry.amountCents),
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            Text(categoryLabel(entry.category)),
            Text(note),
            Text(formatDateLabel(entry.transactionDate, today)),
          ],
        ),
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}

class UndoDeleteBanner extends StatelessWidget {
  const UndoDeleteBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<LedgerUiController>();
    if (controller.undoDeleteState == null) {
      return const SizedBox.shrink();
    }

    return Material(
      color: Theme.of(context).colorScheme.inverseSurface,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: Text(
                '已删除这笔账',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onInverseSurface,
                ),
              ),
            ),
            TextButton.icon(
              key: const Key('undo-delete-action'),
              onPressed: controller.undoDelete,
              icon: const Icon(Icons.undo),
              label: const Text('撤销'),
            ),
          ],
        ),
      ),
    );
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader({required this.title, this.action, super.key});

  final String title;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        ..._present(action),
      ],
    );
  }
}

Iterable<Widget> _present(Widget? widget) {
  return widget == null ? const <Widget>[] : <Widget>[widget];
}

Future<void> _handleBackupSelection(BuildContext context, String value) async {
  final controller = context.read<LedgerUiController>();
  try {
    if (value == 'backup') {
      final result = await controller.exportBackup();
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('备份已保存：${result.fileName}')));
      return;
    }

    if (value != 'restore') {
      return;
    }

    final backups = await controller.listBackups();
    if (!context.mounted) {
      return;
    }
    if (backups.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('没有可恢复的本地备份。')));
      return;
    }

    final selected = await _showBackupPicker(context, backups);
    if (selected == null || !context.mounted) {
      return;
    }
    final confirmed = await _confirmBackupRestore(context, selected);
    if (!confirmed || !context.mounted) {
      return;
    }

    final result = await controller.importBackup(selected.filePath);
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '已恢复 ${result.transactionCount} 笔账目'
          '${result.deletedCount == 0 ? '' : '（含 ${result.deletedCount} 笔已删除账目）'}。',
        ),
      ),
    );
  } on BackupException catch (error) {
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(error.message)));
  } on Object {
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('备份操作失败，请稍后重试。')));
  }
}

Future<BackupFileInfo?> _showBackupPicker(
  BuildContext context,
  List<BackupFileInfo> backups,
) {
  return showDialog<BackupFileInfo>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        key: const Key('backup-restore-dialog'),
        title: const Text('选择备份'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 360, minWidth: 280),
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: backups.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final backup = backups[index];
              return ListTile(
                key: Key('backup-file-${backup.fileName}'),
                leading: const Icon(Icons.description_outlined),
                title: Text(backup.fileName),
                subtitle: Text(
                  '${_formatDateTime(backup.modifiedAt)} · '
                  '${_formatFileSize(backup.sizeBytes)}',
                ),
                onTap: () => Navigator.of(dialogContext).pop(backup),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('取消'),
          ),
        ],
      );
    },
  );
}

Future<bool> _confirmBackupRestore(
  BuildContext context,
  BackupFileInfo backup,
) async {
  return await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          key: const Key('backup-restore-confirmation'),
          title: const Text('恢复这份备份？'),
          content: Text('恢复后将用备份中的 ${backup.fileName} 替换当前账本。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('取消'),
            ),
            FilledButton.icon(
              key: const Key('confirm-backup-restore'),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              icon: const Icon(Icons.restore),
              label: const Text('恢复'),
            ),
          ],
        ),
      ) ??
      false;
}

String _formatDateTime(DateTime value) {
  final local = value.toLocal();
  String twoDigits(int number) => number.toString().padLeft(2, '0');

  return '${local.year}-${twoDigits(local.month)}-${twoDigits(local.day)} '
      '${twoDigits(local.hour)}:${twoDigits(local.minute)}';
}

String _formatFileSize(int bytes) {
  if (bytes < 1024) {
    return '$bytes B';
  }
  if (bytes < 1024 * 1024) {
    return '${(bytes / 1024).toStringAsFixed(1)} KB';
  }
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

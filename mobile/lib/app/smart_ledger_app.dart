import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/import/import_coordinator.dart';
import '../ui/ai/ai_classification_page.dart';
import '../ui/editor/transaction_editor_page.dart';
import '../ui/batch/batch_confirm_page.dart';
import '../ui/import/import_entry_page.dart';
import '../ui/ledger_ui_controller.dart';
import '../ui/ocr/ocr_capture.dart';
import '../ui/ocr/ocr_page.dart';
import '../ui/shared/ledger_shell.dart';
import 'app_routes.dart';

class SmartLedgerApp extends StatelessWidget {
  const SmartLedgerApp({required this.controller, this.ocrCapture, super.key});

  final LedgerUiController controller;
  final OcrCaptureService? ocrCapture;

  @override
  Widget build(BuildContext context) {
    final capture = ocrCapture ?? AndroidOcrCaptureService();
    final app = MaterialApp(
      title: 'Smart Ledger',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0F7B6C),
          brightness: Brightness.light,
        ),
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          filled: true,
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(44),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
      ),
      initialRoute: AppRoutes.home,
      routes: {
        AppRoutes.home: (_) => const _LedgerShellRoute(),
        AppRoutes.transactions: (_) => const _LedgerShellRoute(initialIndex: 1),
        AppRoutes.budget: (_) => const _LedgerShellRoute(initialIndex: 2),
        AppRoutes.statistics: (_) => const _LedgerShellRoute(initialIndex: 3),
        AppRoutes.newTransaction: (_) => const TransactionEditorPage(),
        AppRoutes.editTransaction: (_) => const TransactionEditorPage(),
        AppRoutes.ocr: (context) {
          final controller = context.read<LedgerUiController>();
          return OcrPage(
            capture: capture,
            today: controller.today,
            onContinueToConfirmation: (input) async {
              final prepared = controller.prepareBatchDraftFromInput(input);
              if (!prepared) {
                return false;
              }
              await Navigator.of(context).pushNamed(AppRoutes.batchConfirm);
              return controller.draft == null &&
                  controller.batchDraft == null &&
                  controller.transactionSaveStatus.isSaved;
            },
          );
        },
        AppRoutes.aiClassification: (context) {
          final controller = context.read<LedgerUiController>();
          return AiClassificationPage(
            today: controller.today,
            onContinueToConfirmation:
                (input, {required type, required categoryCode}) async {
                  final prepared = controller.prepareDraftFromInput(input);
                  if (!prepared) {
                    return false;
                  }
                  if (controller.draft?.type != type) {
                    controller.updateType(type);
                  }
                  if (controller.draft?.category != categoryCode) {
                    controller.updateCategory(categoryCode);
                  }
                  // AI 确认页已让用户核对金额；无货币单位只是提示，不应再次阻塞同一流程。
                  controller.acknowledgeIssue('BARE_AMOUNT');
                  controller.acknowledgeIssue(
                    'LOCAL_CLASSIFICATION_SUGGESTION',
                  );
                  await Navigator.of(context)
                      .pushNamed(AppRoutes.newTransaction);
                  return controller.draft == null &&
                      controller.transactionSaveStatus.isSaved;
                },
          );
        },
        AppRoutes.importEntry: (context) {
          final controller = context.read<LedgerUiController>();
          return ImportEntryPage(
            coordinator: ImportCoordinator(repository: controller.repository),
            onBatchSaved: controller.refresh,
          );
        },
        AppRoutes.batchConfirm: (context) {
          final controller = context.read<LedgerUiController>();
          final batch = controller.batchDraft;
          if (batch == null) {
            return Scaffold(
              appBar: AppBar(title: const Text('批量确认')),
              body: Center(child: Text('没有正在确认的批量账目')),
            );
          }
          return PopScope<Object?>(
            canPop: true,
            onPopInvokedWithResult: (didPop, _) {
              if (didPop) {
                controller.discardBatchDraft();
              }
            },
            child: BatchConfirmPage(
              result: batch,
              today: controller.today,
              onSubmitFailureMessage: () => controller.feedbackMessage,
              onConfirm: (transactions) =>
                  controller.saveBatchTransactions(transactions),
            ),
          );
        },
      },
    );

    return ChangeNotifierProvider<LedgerUiController>.value(
      value: controller,
      child: app,
    );
  }
}

class _LedgerShellRoute extends StatelessWidget {
  const _LedgerShellRoute({this.initialIndex = 0});

  final int initialIndex;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(child: LedgerShell(initialIndex: initialIndex)),
        Positioned(
          right: 16,
          bottom: 88,
          child: SafeArea(
            top: false,
            left: false,
            right: false,
            child: Semantics(
              button: true,
              label: '记账工具，打开拍照识别、智能分类和导入账单菜单',
              child: FloatingActionButton.extended(
                key: const Key('open-accounting-tools'),
                heroTag: 'open-accounting-tools-hero',
                tooltip: '记账工具',
                onPressed: () => _showAccountingTools(context),
                icon: const Icon(Icons.add_task),
                label: const Text('记账工具'),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

void _showAccountingTools(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) {
      return _AccountingToolsSheet(
        onSelected: (routeName) {
          Navigator.of(sheetContext).pop();
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (context.mounted) {
              Navigator.of(context).pushNamed(routeName);
            }
          });
        },
      );
    },
  );
}

class _AccountingToolsSheet extends StatelessWidget {
  const _AccountingToolsSheet({required this.onSelected});

  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '记账工具',
                    style: Theme.of(context).textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                IconButton(
                  key: const Key('accounting-tools-cancel'),
                  tooltip: '取消',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            _ToolMenuItem(
              key: const Key('accounting-tool-ocr'),
              icon: Icons.document_scanner_outlined,
              title: '拍照识别',
              description: '拍摄或选择账单图片，在本机识别文字。',
              onTap: () => onSelected(AppRoutes.ocr),
            ),
            _ToolMenuItem(
              key: const Key('accounting-tool-ai-classification'),
              icon: Icons.auto_awesome,
              title: '智能分类',
              description: '输入一笔账目，获得本地分类建议。',
              onTap: () => onSelected(AppRoutes.aiClassification),
            ),
            _ToolMenuItem(
              key: const Key('accounting-tool-import'),
              icon: Icons.file_open,
              title: '导入账单',
              description: '选择支持的 CSV 账单文件，批量导入。',
              onTap: () => onSelected(AppRoutes.importEntry),
            ),
          ],
        ),
      ),
    );
  }
}

class _ToolMenuItem extends StatelessWidget {
  const _ToolMenuItem({
    required this.icon,
    required this.title,
    required this.description,
    required this.onTap,
    super.key,
  });

  final IconData icon;
  final String title;
  final String description;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '$title，$description',
      child: ListTile(
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text(description),
        contentPadding: const EdgeInsets.symmetric(horizontal: 4),
        onTap: onTap,
      ),
    );
  }
}

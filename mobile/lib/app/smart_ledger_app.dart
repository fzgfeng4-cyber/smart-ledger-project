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
            child: FloatingActionButton(
              key: const Key('open-import-entry'),
              heroTag: 'open-import-entry-hero',
              tooltip: '导入 CSV 账单',
              onPressed: () {
                Navigator.of(context).pushNamed(AppRoutes.importEntry);
              },
              child: const Icon(Icons.file_open),
            ),
          ),
        ),
        Positioned(
          right: 20,
          bottom: 148,
          child: SafeArea(
            top: false,
            left: false,
            right: false,
            child: FloatingActionButton.small(
              key: const Key('open-ai-classification'),
              heroTag: 'open-ai-classification-hero',
              tooltip: 'AI 分类输入',
              onPressed: () {
                Navigator.of(context).pushNamed(AppRoutes.aiClassification);
              },
              child: const Icon(Icons.auto_awesome),
            ),
          ),
        ),
        Positioned(
          right: 20,
          bottom: 204,
          child: SafeArea(
            top: false,
            left: false,
            right: false,
            child: FloatingActionButton.small(
              key: const Key('open-ocr-entry'),
              heroTag: 'open-ocr-entry-hero',
              tooltip: '拍照识别账单',
              onPressed: () {
                Navigator.of(context).pushNamed(AppRoutes.ocr);
              },
              child: const Icon(Icons.document_scanner_outlined),
            ),
          ),
        ),
      ],
    );
  }
}

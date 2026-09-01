import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../ui/editor/transaction_editor_page.dart';
import '../ui/ledger_ui_controller.dart';
import '../ui/shared/ledger_shell.dart';
import 'app_routes.dart';

class SmartLedgerApp extends StatelessWidget {
  const SmartLedgerApp({required this.controller, super.key});

  final LedgerUiController controller;

  @override
  Widget build(BuildContext context) {
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
        AppRoutes.home: (_) => const LedgerShell(),
        AppRoutes.transactions: (_) => const LedgerShell(initialIndex: 1),
        AppRoutes.newTransaction: (_) => const TransactionEditorPage(),
        AppRoutes.editTransaction: (_) => const TransactionEditorPage(),
      },
    );

    return ChangeNotifierProvider<LedgerUiController>.value(
      value: controller,
      child: app,
    );
  }
}

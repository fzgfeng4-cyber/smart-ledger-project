import 'package:flutter/material.dart';

import '../home/home_page.dart';
import '../budget/budget_page.dart';
import '../statistics/statistics_page.dart';
import '../transactions/transactions_page.dart';

class LedgerShell extends StatefulWidget {
  const LedgerShell({this.initialIndex = 0, super.key});

  final int initialIndex;

  @override
  State<LedgerShell> createState() => _LedgerShellState();
}

class _LedgerShellState extends State<LedgerShell> {
  late int _selectedIndex;

  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.initialIndex;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _selectedIndex,
        children: [
          const HomePage(),
          const TransactionsPage(),
          BudgetOverviewPage(isActive: _selectedIndex == 2),
          StatisticsPage(isActive: _selectedIndex == 3),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        key: const Key('main-navigation'),
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) {
          setState(() => _selectedIndex = index);
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: '首页',
          ),
          NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            selectedIcon: Icon(Icons.receipt_long),
            label: '账单',
          ),
          NavigationDestination(
            icon: Icon(Icons.account_balance_wallet_outlined),
            selectedIcon: Icon(Icons.account_balance_wallet),
            label: '预算',
          ),
          NavigationDestination(
            icon: Icon(Icons.bar_chart_outlined),
            selectedIcon: Icon(Icons.bar_chart),
            label: '统计',
          ),
        ],
      ),
    );
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/app_routes.dart';
import '../../domain/budget/budget_calculation.dart';
import '../ledger_ui_controller.dart';
import '../models/ledger_ui_models.dart';
import '../shared/ui_components.dart';
import '../shared/ledger_formatters.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late final TextEditingController _quickInputController;
  late final TextEditingController _searchController;

  @override
  void initState() {
    super.initState();
    _quickInputController = TextEditingController();
    _searchController = TextEditingController();
  }

  @override
  void dispose() {
    _quickInputController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<LedgerUiController>(
      builder: (context, controller, _) {
        final recentEntries = controller.recentEntries;
        final searchEntries = controller.searchEntries;
        final hasActiveSearch = controller.hasActiveSearch;
        return SafeArea(
          child: SingleChildScrollView(
            key: const Key('home-page'),
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 96),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const AppTopBar(title: 'Smart Ledger'),
                  const SizedBox(height: 16),
                  _SearchCard(
                    textController: _searchController,
                    statusText: controller.searchStatusMessage,
                    statusIsError: controller.searchError != null,
                    isBusy: controller.isBusy || controller.isBackupBusy,
                    isSearching: controller.isSearching,
                  ),
                  const SizedBox(height: 14),
                  _StatsRow(controller: controller),
                  const SizedBox(height: 18),
                  _BudgetSummarySection(
                    month: controller.budgetMonth,
                    calculations: controller.budgetCalculations,
                    isBusy: controller.isBudgetBusy,
                    errorMessage: controller.budgetError,
                    onOpenBudget: () =>
                        Navigator.of(context).pushNamed(AppRoutes.budget),
                    onRetry: () => unawaited(controller.refreshBudgets()),
                  ),
                  const SizedBox(height: 18),
                  _QuickInputCard(
                    textController: _quickInputController,
                    errorText: controller.quickInputError,
                  ),
                  const SizedBox(height: 22),
                  if (hasActiveSearch)
                    _SearchResultsSection(
                      controller: controller,
                      searchEntries: searchEntries,
                      onRetry: () => unawaited(
                        controller.search(controller.searchQueryText ?? ''),
                      ),
                    )
                  else
                    _RecentEntriesSection(
                      controller: controller,
                      recentEntries: recentEntries,
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SearchResultsSection extends StatelessWidget {
  const _SearchResultsSection({
    required this.controller,
    required this.searchEntries,
    required this.onRetry,
  });

  final LedgerUiController controller;
  final List<UiLedgerEntry> searchEntries;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader(title: '搜索结果'),
        const SizedBox(height: 8),
        const UndoDeleteBanner(),
        if (controller.isSearching)
          const _SearchLoadingState()
        else if (controller.searchError != null)
          _SearchErrorState(message: controller.searchError!, onRetry: onRetry)
        else if (searchEntries.isEmpty)
          const _SearchEmptyState()
        else
          ...searchEntries.map(
            (entry) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: TransactionTile(
                entry: entry,
                today: controller.today,
                onTap: () {
                  controller.startEditing(entry);
                  Navigator.of(context).pushNamed(AppRoutes.editTransaction);
                },
              ),
            ),
          ),
      ],
    );
  }
}

class _RecentEntriesSection extends StatelessWidget {
  const _RecentEntriesSection({
    required this.controller,
    required this.recentEntries,
  });

  final LedgerUiController controller;
  final List<UiLedgerEntry> recentEntries;

  @override
  Widget build(BuildContext context) {
    if (controller.listStatus == LedgerListStatus.loading &&
        recentEntries.isEmpty) {
      return const _HomeLoadingState();
    }
    if (controller.listStatus == LedgerListStatus.error &&
        recentEntries.isEmpty) {
      return _HomeErrorState(
        message: controller.loadError ?? '账目暂时加载失败，请重试。',
        onRetry: controller.refresh,
      );
    }
    if (recentEntries.isEmpty) {
      return const Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [UndoDeleteBanner(), _HomeEmptyState()],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (controller.loadError != null)
          _HomeRefreshErrorBanner(
            message: controller.loadError!,
            onRetry: controller.refresh,
          ),
        SectionHeader(
          title: '最近账目',
          action: TextButton.icon(
            key: const Key('view-all-transactions'),
            onPressed: () =>
                Navigator.of(context).pushNamed(AppRoutes.transactions),
            icon: const Icon(Icons.receipt_long),
            label: const Text('查看全部'),
          ),
        ),
        const SizedBox(height: 8),
        const UndoDeleteBanner(),
        ...recentEntries.map(
          (entry) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: TransactionTile(
              entry: entry,
              today: controller.today,
              onTap: () {
                controller.startEditing(entry);
                Navigator.of(context).pushNamed(AppRoutes.editTransaction);
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _BudgetSummarySection extends StatelessWidget {
  const _BudgetSummarySection({
    required this.month,
    required this.calculations,
    required this.isBusy,
    required this.errorMessage,
    required this.onOpenBudget,
    required this.onRetry,
  });

  final String month;
  final List<BudgetCalculation> calculations;
  final bool isBusy;
  final String? errorMessage;
  final VoidCallback onOpenBudget;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          title: '本月预算',
          action: TextButton.icon(
            key: const Key('home-budget-entry'),
            onPressed: onOpenBudget,
            icon: const Icon(Icons.account_balance_wallet_outlined),
            label: const Text('管理预算'),
          ),
        ),
        const SizedBox(height: 8),
        if (isBusy && calculations.isEmpty)
          const _BudgetSummaryLoadingState()
        else if (errorMessage != null && calculations.isEmpty)
          _BudgetSummaryErrorState(message: errorMessage!, onRetry: onRetry)
        else if (calculations.isEmpty)
          const _BudgetSummaryEmptyState()
        else
          _BudgetSummaryCard(
            month: month,
            calculations: calculations,
            isBusy: isBusy,
            errorMessage: errorMessage,
          ),
      ],
    );
  }
}

class _BudgetSummaryLoadingState extends StatelessWidget {
  const _BudgetSummaryLoadingState();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      key: const Key('home-budget-loading'),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: const Padding(
        padding: EdgeInsets.all(16),
        child: Row(
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 12),
            Expanded(child: Text('预算加载中...')),
          ],
        ),
      ),
    );
  }
}

class _BudgetSummaryErrorState extends StatelessWidget {
  const _BudgetSummaryErrorState({
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      key: const Key('home-budget-error-state'),
      decoration: BoxDecoration(
        color: colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colorScheme.error),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.error_outline, color: colorScheme.onErrorContainer),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    message,
                    style: TextStyle(color: colorScheme.onErrorContainer),
                  ),
                ),
              ],
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                key: const Key('home-budget-retry'),
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('重试'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BudgetSummaryEmptyState extends StatelessWidget {
  const _BudgetSummaryEmptyState();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      key: const Key('home-budget-empty-state'),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.account_balance_wallet_outlined,
              color: colorScheme.primary,
            ),
            const SizedBox(width: 8),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('本月还没有预算'),
                  SizedBox(height: 4),
                  Text('设置预算后，这里会显示已使用、剩余和预计耗尽天数。'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BudgetSummaryCard extends StatelessWidget {
  const _BudgetSummaryCard({
    required this.month,
    required this.calculations,
    required this.isBusy,
    required this.errorMessage,
  });

  final String month;
  final List<BudgetCalculation> calculations;
  final bool isBusy;
  final String? errorMessage;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final totals = _summarizeBudgets(calculations);
    final progress = totals.budgetAmountCents <= 0
        ? totals.usedCents > 0
              ? 1.0
              : 0.0
        : (totals.usedCents / totals.budgetAmountCents)
              .clamp(0.0, 1.0)
              .toDouble();
    final progressColor = totals.overspentCents > 0
        ? colorScheme.error
        : colorScheme.primary;

    return DecoratedBox(
      key: const Key('home-budget-summary'),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: totals.overspentCents > 0
              ? colorScheme.error
              : colorScheme.outlineVariant,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '预算使用情况',
                    style: Theme.of(context).textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                if (isBusy)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '$month · ${calculations.length} 项启用预算',
              key: const Key('home-budget-month'),
              style: TextStyle(color: colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 14),
            Semantics(
              label: '预算使用进度',
              value: '${(progress * 100).round()}%',
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 8,
                color: progressColor,
                backgroundColor: colorScheme.surfaceContainerHighest,
              ),
            ),
            const SizedBox(height: 14),
            LayoutBuilder(
              builder: (context, constraints) {
                final metricWidth = constraints.maxWidth < 420
                    ? (constraints.maxWidth - 12) / 2
                    : (constraints.maxWidth - 24) / 3;
                return Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    SizedBox(
                      width: metricWidth,
                      child: _BudgetSummaryMetric(
                        key: const Key('home-budget-total'),
                        label: '预算总额',
                        amountCents: totals.budgetAmountCents,
                      ),
                    ),
                    SizedBox(
                      width: metricWidth,
                      child: _BudgetSummaryMetric(
                        key: const Key('home-budget-used'),
                        label: '已使用',
                        amountCents: totals.usedCents,
                        amountColor: totals.overspentCents > 0
                            ? colorScheme.error
                            : null,
                      ),
                    ),
                    SizedBox(
                      width: metricWidth,
                      child: _BudgetSummaryMetric(
                        key: const Key('home-budget-remaining'),
                        label: '剩余',
                        amountCents: totals.remainingCents,
                        amountColor: totals.overspentCents > 0
                            ? colorScheme.error
                            : null,
                      ),
                    ),
                  ],
                );
              },
            ),
            if (totals.overspentCents > 0) ...[
              const SizedBox(height: 14),
              _BudgetSummaryNotice(
                key: const Key('home-budget-overspent'),
                icon: Icons.warning_amber_rounded,
                color: colorScheme.error,
                text: '已超支 ${formatMoneyCents(totals.overspentCents)}',
              ),
            ],
            if (totals.estimatedDays != null) ...[
              const SizedBox(height: 10),
              _BudgetSummaryNotice(
                key: const Key('home-budget-estimated-days'),
                icon: Icons.schedule_outlined,
                color: colorScheme.onSurfaceVariant,
                text:
                    '预计耗尽：${totals.estimatedDays} 天'
                    '${calculations.length > 1 ? '（最早）' : ''}',
              ),
            ] else if (totals.usedCents == 0) ...[
              const SizedBox(height: 10),
              const _BudgetSummaryNotice(
                key: Key('home-budget-no-spending'),
                icon: Icons.info_outline,
                text: '暂无消费，暂不预测耗尽时间',
              ),
            ] else if (totals.remainingCents == 0) ...[
              const SizedBox(height: 10),
              const _BudgetSummaryNotice(
                key: Key('home-budget-used-up'),
                icon: Icons.check_circle_outline,
                text: '预算已用尽',
              ),
            ],
            if (errorMessage != null) ...[
              const SizedBox(height: 10),
              _BudgetSummaryNotice(
                icon: Icons.error_outline,
                color: colorScheme.error,
                text: errorMessage!,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _BudgetSummaryMetric extends StatelessWidget {
  const _BudgetSummaryMetric({
    required this.label,
    required this.amountCents,
    this.amountColor,
    super.key,
  });

  final String label;
  final int amountCents;
  final Color? amountColor;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 3),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            formatMoneyCents(amountCents),
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(color: amountColor, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}

class _BudgetSummaryNotice extends StatelessWidget {
  const _BudgetSummaryNotice({
    required this.icon,
    required this.text,
    this.color,
    super.key,
  });

  final IconData icon;
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final foregroundColor =
        color ?? Theme.of(context).colorScheme.onSurfaceVariant;
    return Semantics(
      container: true,
      label: text,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: foregroundColor),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: foregroundColor,
                fontWeight: color == null ? null : FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

final class _BudgetSummaryTotals {
  const _BudgetSummaryTotals({
    required this.budgetAmountCents,
    required this.usedCents,
    required this.remainingCents,
    required this.overspentCents,
    required this.estimatedDays,
  });

  final int budgetAmountCents;
  final int usedCents;
  final int remainingCents;
  final int overspentCents;
  final int? estimatedDays;
}

_BudgetSummaryTotals _summarizeBudgets(
  Iterable<BudgetCalculation> calculations,
) {
  var budgetAmountCents = 0;
  var usedCents = 0;
  var remainingCents = 0;
  var overspentCents = 0;
  int? estimatedDays;

  for (final calculation in calculations) {
    budgetAmountCents += calculation.budgetAmountCents;
    usedCents += calculation.usedCents;
    remainingCents += calculation.remainingCents;
    overspentCents += calculation.overspentCents;
    final days = calculation.estimatedDaysToExhaustion;
    if (days != null && (estimatedDays == null || days < estimatedDays)) {
      estimatedDays = days;
    }
  }

  return _BudgetSummaryTotals(
    budgetAmountCents: budgetAmountCents,
    usedCents: usedCents,
    remainingCents: remainingCents,
    overspentCents: overspentCents,
    estimatedDays: estimatedDays,
  );
}

class _SearchCard extends StatelessWidget {
  const _SearchCard({
    required this.textController,
    required this.statusText,
    required this.statusIsError,
    required this.isBusy,
    required this.isSearching,
  });

  final TextEditingController textController;
  final String? statusText;
  final bool statusIsError;
  final bool isBusy;
  final bool isSearching;

  @override
  Widget build(BuildContext context) {
    final controller = context.read<LedgerUiController>();
    final canSubmit = !isBusy && !isSearching;

    return Semantics(
      container: true,
      label: '搜索账目',
      child: DecoratedBox(
        key: const Key('home-search-card'),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainer,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: ValueListenableBuilder<TextEditingValue>(
                      valueListenable: textController,
                      builder: (context, value, _) {
                        return TextField(
                          key: const Key('search-input'),
                          controller: textController,
                          textInputAction: TextInputAction.search,
                          minLines: 1,
                          maxLines: 1,
                          decoration: InputDecoration(
                            hintText: '搜索账目',
                            filled: true,
                            isDense: true,
                            prefixIcon: const Icon(Icons.search),
                            suffixIcon: IconButton(
                              key: const Key('search-clear'),
                              tooltip: '清除搜索',
                              onPressed: canSubmit && value.text.isNotEmpty
                                  ? () => _clear(context, controller)
                                  : null,
                              icon: const Icon(Icons.close),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                          ),
                          onSubmitted: (_) => _submit(context, controller),
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    key: const Key('search-submit'),
                    tooltip: '搜索',
                    onPressed: canSubmit
                        ? () => _submit(context, controller)
                        : null,
                    icon: const Icon(Icons.search),
                  ),
                ],
              ),
              if (statusText != null) ...[
                const SizedBox(height: 6),
                Text(
                  statusText!,
                  style: TextStyle(
                    color: statusIsError
                        ? Theme.of(context).colorScheme.error
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _submit(BuildContext context, LedgerUiController controller) {
    FocusManager.instance.primaryFocus?.unfocus();
    unawaited(controller.search(textController.text));
  }

  void _clear(BuildContext context, LedgerUiController controller) {
    FocusManager.instance.primaryFocus?.unfocus();
    textController.clear();
    controller.clearSearch();
  }
}

class _StatsRow extends StatelessWidget {
  const _StatsRow({required this.controller});

  final LedgerUiController controller;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: StatCard(
            label: '今天支出',
            amountCents: controller.todayExpenseCents,
            icon: Icons.today,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: StatCard(
            label: '本月支出',
            amountCents: controller.monthExpenseCents,
            icon: Icons.calendar_month,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: StatCard(
            label: '本月收入',
            amountCents: controller.monthIncomeCents,
            icon: Icons.payments,
          ),
        ),
      ],
    );
  }
}

class _QuickInputCard extends StatelessWidget {
  const _QuickInputCard({
    required this.textController,
    required this.errorText,
  });

  final TextEditingController textController;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    final controller = context.read<LedgerUiController>();
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '快速记账',
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            LayoutBuilder(
              builder: (context, constraints) {
                final input = TextField(
                  key: const Key('quick-input'),
                  controller: textController,
                  textInputAction: TextInputAction.done,
                  minLines: 1,
                  maxLines: 3,
                  decoration: InputDecoration(
                    hintText: '例如：35块买菜',
                    errorText: errorText,
                    filled: true,
                  ),
                  onSubmitted: (_) => _submit(context, controller),
                );
                final button = FilledButton.icon(
                  key: const Key('quick-submit'),
                  onPressed: () => _submit(context, controller),
                  icon: const Icon(Icons.arrow_forward),
                  label: const Text('识别'),
                );
                final batchButton = OutlinedButton.icon(
                  key: const Key('batch-entry-button'),
                  onPressed: () => _submitBatch(context, controller),
                  icon: const Icon(Icons.playlist_add),
                  label: const Text('批量记账'),
                );

                if (constraints.maxWidth < 420) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      input,
                      const SizedBox(height: 10),
                      SizedBox(height: 48, child: button),
                      const SizedBox(height: 8),
                      SizedBox(height: 44, child: batchButton),
                    ],
                  );
                }

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: input),
                        const SizedBox(width: 10),
                        SizedBox(width: 104, height: 56, child: button),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: SizedBox(
                        width: 132,
                        height: 44,
                        child: batchButton,
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  void _submit(BuildContext context, LedgerUiController controller) {
    final prepared = controller.prepareDraftFromInput(textController.text);
    if (prepared) {
      FocusManager.instance.primaryFocus?.unfocus();
      Navigator.of(context).pushNamed(AppRoutes.newTransaction);
    }
  }

  void _submitBatch(BuildContext context, LedgerUiController controller) {
    final prepared = controller.prepareBatchDraftFromInput(textController.text);
    if (prepared) {
      FocusManager.instance.primaryFocus?.unfocus();
      Navigator.of(context).pushNamed(AppRoutes.batchConfirm);
    }
  }
}

class _HomeEmptyState extends StatelessWidget {
  const _HomeEmptyState();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      key: const Key('home-empty-state'),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('还没有账目'),
            SizedBox(height: 6),
            Text('输入第一笔，例如“35块买菜”。'),
          ],
        ),
      ),
    );
  }
}

class _SearchEmptyState extends StatelessWidget {
  const _SearchEmptyState();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      key: const Key('search-empty-state'),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Padding(
        padding: EdgeInsets.all(16),
        child: Text('没有找到符合条件的账目。'),
      ),
    );
  }
}

class _SearchLoadingState extends StatelessWidget {
  const _SearchLoadingState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      key: Key('search-loading-state'),
      child: Padding(
        padding: EdgeInsets.all(20),
        child: CircularProgressIndicator(),
      ),
    );
  }
}

class _SearchErrorState extends StatelessWidget {
  const _SearchErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      key: const Key('search-error-state'),
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
            const SizedBox(height: 8),
            TextButton.icon(
              key: const Key('search-retry'),
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

class _HomeLoadingState extends StatelessWidget {
  const _HomeLoadingState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      key: Key('home-loading-state'),
      child: Padding(
        padding: EdgeInsets.all(24),
        child: CircularProgressIndicator(),
      ),
    );
  }
}

class _HomeErrorState extends StatelessWidget {
  const _HomeErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      key: const Key('home-error-state'),
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
            const SizedBox(height: 8),
            TextButton.icon(
              key: const Key('home-retry'),
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

class _HomeRefreshErrorBanner extends StatelessWidget {
  const _HomeRefreshErrorBanner({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DecoratedBox(
        key: const Key('home-refresh-error'),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.errorContainer,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Expanded(child: Text(message)),
              IconButton(
                key: const Key('home-refresh-retry'),
                tooltip: '重试',
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

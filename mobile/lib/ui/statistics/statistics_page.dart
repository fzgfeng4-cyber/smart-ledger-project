import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../domain/statistics/statistics_summary.dart';
import '../ledger_ui_controller.dart';
import '../shared/ledger_formatters.dart';
import '../shared/ui_components.dart';

class StatisticsPage extends StatefulWidget {
  const StatisticsPage({this.isActive = true, super.key});

  final bool isActive;

  @override
  State<StatisticsPage> createState() => _StatisticsPageState();
}

class _StatisticsPageState extends State<StatisticsPage> {
  @override
  void initState() {
    super.initState();
    _refreshIfActive();
  }

  @override
  void didUpdateWidget(covariant StatisticsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.isActive && widget.isActive) {
      _refreshIfActive();
    }
  }

  void _refreshIfActive() {
    if (!widget.isActive) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.isActive) {
        context.read<LedgerUiController>().refreshStatistics();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<LedgerUiController>(
      builder: (context, controller, _) {
        final summary = controller.statisticsSummary;
        final shouldShowLoading =
            summary == null &&
            controller.statisticsError == null &&
            (controller.isStatisticsBusy ||
                controller.isStatisticsRefreshPending ||
                (widget.isActive && !controller.hasRequestedStatistics));
        return SafeArea(
          child: CustomScrollView(
            key: const Key('statistics-page'),
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 96),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    const AppTopBar(title: '统计'),
                    const SizedBox(height: 16),
                    if (shouldShowLoading)
                      const Center(
                        key: Key('statistics-loading'),
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: CircularProgressIndicator(),
                        ),
                      )
                    else if (controller.statisticsError != null &&
                        summary == null)
                      _StatisticsErrorState(
                        message: controller.statisticsError!,
                        onRetry: controller.refreshStatistics,
                      )
                    else if (summary != null)
                      _StatisticsSummaryView(summary: summary)
                    else
                      const _StatisticsEmptyState(),
                  ]),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _StatisticsSummaryView extends StatelessWidget {
  const _StatisticsSummaryView({required this.summary});

  final StatisticsSummary summary;

  @override
  Widget build(BuildContext context) {
    final categories = summary.expenseCategories;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: StatCard(
                label: '本月支出',
                amountCents: summary.expenseTotalCents,
                icon: Icons.arrow_upward,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: StatCard(
                label: '本月收入',
                amountCents: summary.incomeTotalCents,
                icon: Icons.arrow_downward,
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        const SectionHeader(title: '分类占比'),
        const SizedBox(height: 8),
        if (categories.isEmpty)
          const _StatisticsEmptyState()
        else
          ...categories.map(
            (category) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _CategoryProportionTile(category: category),
            ),
          ),
      ],
    );
  }
}

class _CategoryProportionTile extends StatelessWidget {
  const _CategoryProportionTile({required this.category});

  final ExpenseCategoryStatistics category;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final percentage = category.percentage;
    return DecoratedBox(
      key: Key('statistics-category-${category.code}'),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    category.label,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                Text(formatMoneyCents(category.amountCents)),
                const SizedBox(width: 8),
                Text('${percentage.toStringAsFixed(1)}%'),
              ],
            ),
            const SizedBox(height: 8),
            Semantics(
              label: '${category.label}占支出${percentage.toStringAsFixed(1)}%',
              value: '${percentage.toStringAsFixed(1)}%',
              child: LinearProgressIndicator(
                value: category.proportion.clamp(0.0, 1.0),
                minHeight: 8,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatisticsEmptyState extends StatelessWidget {
  const _StatisticsEmptyState();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      key: const Key('statistics-empty-state'),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Padding(
        padding: EdgeInsets.all(16),
        child: Text('本月还没有支出记录。'),
      ),
    );
  }
}

class _StatisticsErrorState extends StatelessWidget {
  const _StatisticsErrorState({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      key: const Key('statistics-error-state'),
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
              key: const Key('statistics-retry'),
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

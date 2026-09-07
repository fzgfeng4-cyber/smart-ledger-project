import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../domain/statistics/statistics_summary.dart';
import '../../domain/statistics/statistics_time_series.dart';
import '../ledger_ui_controller.dart';
import '../shared/ledger_formatters.dart';
import '../shared/ui_components.dart';
import 'statistics_chart_widgets.dart';

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
        final monthlySeries = controller.monthlyStatisticsTimeSeries;
        final yearlySeries = controller.yearlyStatisticsTimeSeries;
        final statisticsIsBusy =
            controller.isStatisticsBusy ||
            controller.isStatisticsRefreshPending;
        final hasCompleteStatistics =
            summary != null && monthlySeries != null && yearlySeries != null;
        final shouldShowLoading =
            !hasCompleteStatistics &&
            controller.statisticsError == null &&
            (statisticsIsBusy ||
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
                    else if (controller.statisticsError != null)
                      _StatisticsErrorState(
                        message: controller.statisticsError!,
                        onRetry: controller.refreshStatistics,
                      )
                    else if (summary != null)
                      _StatisticsSummaryView(
                        summary: summary,
                        monthlySeries: monthlySeries,
                        yearlySeries: yearlySeries,
                        isRefreshing: statisticsIsBusy,
                      )
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

enum _StatisticsPeriod { month, year }

class _StatisticsSummaryView extends StatefulWidget {
  const _StatisticsSummaryView({
    required this.summary,
    required this.monthlySeries,
    required this.yearlySeries,
    required this.isRefreshing,
  });

  final StatisticsSummary summary;
  final StatisticsTimeSeries? monthlySeries;
  final StatisticsTimeSeries? yearlySeries;
  final bool isRefreshing;

  @override
  State<_StatisticsSummaryView> createState() => _StatisticsSummaryViewState();
}

class _StatisticsSummaryViewState extends State<_StatisticsSummaryView> {
  _StatisticsPeriod _period = _StatisticsPeriod.month;
  bool _showAllBuckets = false;

  StatisticsTimeSeries? get _selectedSeries =>
      _period == _StatisticsPeriod.month
      ? widget.monthlySeries
      : widget.yearlySeries;

  String get _periodName => _period == _StatisticsPeriod.month ? '月度' : '年度';

  String get _periodContext {
    final series = _selectedSeries;
    final date = series == null
        ? null
        : DateTime.tryParse(series.range.startDateInclusive);
    if (date == null) {
      return _period == _StatisticsPeriod.month ? '本月' : '本年';
    }
    return _period == _StatisticsPeriod.month
        ? '本月（${date.year}年${date.month}月）'
        : '本年（${date.year}年）';
  }

  String get _periodAmountPrefix {
    final series = _selectedSeries;
    final date = series == null
        ? null
        : DateTime.tryParse(series.range.startDateInclusive);
    if (date == null) {
      return _period == _StatisticsPeriod.month ? '本月' : '本年';
    }
    return _period == _StatisticsPeriod.month
        ? '${date.year}年${date.month}月'
        : '${date.year}年';
  }

  int get _expenseTotal {
    if (_period == _StatisticsPeriod.month) {
      return widget.summary.expenseTotalCents;
    }
    return _selectedSeries?.buckets.fold<int>(
          0,
          (total, bucket) => total + bucket.expenseTotalCents,
        ) ??
        0;
  }

  int get _incomeTotal {
    if (_period == _StatisticsPeriod.month) {
      return widget.summary.incomeTotalCents;
    }
    return _selectedSeries?.buckets.fold<int>(
          0,
          (total, bucket) => total + bucket.incomeTotalCents,
        ) ??
        0;
  }

  @override
  Widget build(BuildContext context) {
    final series = _selectedSeries;
    final chartTitle = _period == _StatisticsPeriod.month ? '本月趋势' : '年度趋势';
    final categories = widget.summary.expenseCategories;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.isRefreshing) const LinearProgressIndicator(),
        if (widget.isRefreshing) const SizedBox(height: 8),
        Semantics(
          container: true,
          label: '统计周期，当前$_periodName，$_periodContext',
          child: SegmentedButton<_StatisticsPeriod>(
            key: const Key('statistics-period-toggle'),
            segments: const [
              ButtonSegment<_StatisticsPeriod>(
                value: _StatisticsPeriod.month,
                icon: Icon(Icons.calendar_view_day),
                label: KeyedSubtree(
                  key: Key('statistics-monthly-toggle'),
                  child: Text('月度'),
                ),
              ),
              ButtonSegment<_StatisticsPeriod>(
                value: _StatisticsPeriod.year,
                icon: Icon(Icons.calendar_month),
                label: KeyedSubtree(
                  key: Key('statistics-yearly-toggle'),
                  child: Text('年度'),
                ),
              ),
            ],
            selected: {_period},
            onSelectionChanged: (selection) {
              if (selection.isEmpty) {
                return;
              }
              setState(() {
                _period = selection.first;
                _showAllBuckets = false;
              });
            },
          ),
        ),
        const SizedBox(height: 12),
        Text(
          _periodContext,
          key: const Key('statistics-period-label'),
          style: Theme.of(context).textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 10),
        _StatisticsTotals(
          prefix: _periodAmountPrefix,
          expenseTotalCents: _expenseTotal,
          incomeTotalCents: _incomeTotal,
        ),
        const SizedBox(height: 18),
        SectionHeader(title: chartTitle),
        const SizedBox(height: 8),
        StatisticsBarChart(
          key: Key(
            _period == _StatisticsPeriod.month
                ? 'statistics-monthly-chart'
                : 'statistics-annual-chart',
          ),
          title: chartTitle,
          series: series,
          emptyKey: _period == _StatisticsPeriod.month
              ? 'statistics-monthly-chart-empty'
              : 'statistics-annual-chart-empty',
          isLoading: widget.isRefreshing && series == null,
          showAllBuckets: _showAllBuckets,
        ),
        const SizedBox(height: 2),
        SwitchListTile.adaptive(
          key: const Key('statistics-show-all-buckets'),
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: Text(_period == _StatisticsPeriod.month ? '显示全部日期' : '显示全部月份'),
          value: _showAllBuckets,
          onChanged: series == null
              ? null
              : (value) => setState(() => _showAllBuckets = value),
        ),
        const SizedBox(height: 18),
        const SectionHeader(title: '支出分类'),
        const SizedBox(height: 8),
        StatisticsExpensePieChart(
          key: const Key('statistics-expense-pie-chart'),
          title: '支出分类',
          range: widget.summary.range,
          categories: categories,
          expenseTotalCents: widget.summary.expenseTotalCents,
          emptyKey: 'statistics-expense-pie-empty',
        ),
        const SizedBox(height: 18),
        const SectionHeader(title: '分类占比'),
        const SizedBox(height: 8),
        _ExpenseCategoryTable(
          categories: categories,
          empty: categories.isEmpty,
        ),
      ],
    );
  }
}

class _StatisticsTotals extends StatelessWidget {
  const _StatisticsTotals({
    required this.prefix,
    required this.expenseTotalCents,
    required this.incomeTotalCents,
  });

  final String prefix;
  final int expenseTotalCents;
  final int incomeTotalCents;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final itemWidth = constraints.maxWidth >= 460
            ? (constraints.maxWidth - 16) / 3
            : constraints.maxWidth;
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            SizedBox(
              width: itemWidth,
              child: StatCard(
                label: '$prefix支出',
                amountCents: expenseTotalCents,
                icon: Icons.arrow_upward,
              ),
            ),
            SizedBox(
              width: itemWidth,
              child: StatCard(
                label: '$prefix收入',
                amountCents: incomeTotalCents,
                icon: Icons.arrow_downward,
              ),
            ),
            SizedBox(
              width: itemWidth,
              child: _BalanceCard(
                label: '$prefix结余',
                amountCents: incomeTotalCents - expenseTotalCents,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _BalanceCard extends StatelessWidget {
  const _BalanceCard({required this.label, required this.amountCents});

  final String label;
  final int amountCents;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final amountColor = amountCents < 0
        ? colorScheme.error
        : colorScheme.primary;
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
                Icon(Icons.account_balance, size: 18, color: amountColor),
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
                _formatSignedMoney(amountCents),
                style: Theme.of(context).textTheme.titleLarge
                    ?.copyWith(color: amountColor, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ExpenseCategoryTable extends StatelessWidget {
  const _ExpenseCategoryTable({required this.categories, required this.empty});

  final List<ExpenseCategoryStatistics> categories;
  final bool empty;

  @override
  Widget build(BuildContext context) {
    if (empty) {
      return const _StatisticsEmptyState();
    }

    final textTheme = Theme.of(context).textTheme;
    return Table(
      key: const Key('statistics-expense-category-table'),
      columnWidths: const {
        0: FlexColumnWidth(1.4),
        1: FlexColumnWidth(1),
        2: FixedColumnWidth(62),
      },
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      children: [
        TableRow(
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
            ),
          ),
          children: [
            _TableHeaderCell('分类', textTheme),
            _TableHeaderCell('金额', textTheme, alignment: TextAlign.right),
            _TableHeaderCell('占比', textTheme, alignment: TextAlign.right),
          ],
        ),
        ...categories.map(
          (category) => TableRow(
            key: ValueKey('statistics-category-row-${category.code}'),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
              ),
            ),
            children: [
              Semantics(
                label:
                    '${category.label}，金额 ${formatMoneyCents(category.amountCents)}，占比 ${category.percentage.toStringAsFixed(1)}%',
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Text(
                    category.label,
                    key: Key('statistics-category-${category.code}'),
                  ),
                ),
              ),
              _TableBodyCell(
                formatMoneyCents(category.amountCents),
                alignment: TextAlign.right,
              ),
              _TableBodyCell(
                '${category.percentage.toStringAsFixed(1)}%',
                alignment: TextAlign.right,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

Widget _TableHeaderCell(
  String text,
  TextTheme textTheme, {
  TextAlign alignment = TextAlign.left,
}) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Text(
      text,
      textAlign: alignment,
      style: textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w700),
    ),
  );
}

Widget _TableBodyCell(String text, {TextAlign alignment = TextAlign.left}) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: Text(text, textAlign: alignment),
  );
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

String _formatSignedMoney(int cents) {
  if (cents < 0) {
    return '-${formatMoneyCents(cents.abs())}';
  }
  return formatMoneyCents(cents);
}

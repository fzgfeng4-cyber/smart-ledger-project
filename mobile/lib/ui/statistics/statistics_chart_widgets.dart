import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../domain/statistics/statistics_date_range.dart';
import '../../domain/statistics/statistics_summary.dart';
import '../../domain/statistics/statistics_time_series.dart';
import '../shared/ledger_formatters.dart';

class StatisticsBarChart extends StatelessWidget {
  const StatisticsBarChart({
    required this.title,
    required this.series,
    required this.emptyKey,
    required this.isLoading,
    required this.showAllBuckets,
    super.key,
  });

  final String title;
  final StatisticsTimeSeries? series;
  final String emptyKey;
  final bool isLoading;
  final bool showAllBuckets;

  @override
  Widget build(BuildContext context) {
    final data = series;
    final colorScheme = Theme.of(context).colorScheme;
    final expenseColor = colorScheme.error;
    final incomeColor = colorScheme.primary;
    final label = data == null
        ? '$title加载中'
        : '$title，范围 ${data.range.startDateInclusive} 至 '
              '${data.range.endDateExclusive}，支出 '
              '${formatMoneyCents(_totalExpenses(data))}，收入 '
              '${formatMoneyCents(_totalIncome(data))}';

    return Semantics(
      container: true,
      label: label,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: colorScheme.outlineVariant),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
          child: _buildContent(
            context,
            data,
            expenseColor: expenseColor,
            incomeColor: incomeColor,
          ),
        ),
      ),
    );
  }

  Widget _buildContent(
    BuildContext context,
    StatisticsTimeSeries? data, {
    required Color expenseColor,
    required Color incomeColor,
  }) {
    if (isLoading || data == null) {
      return const SizedBox(
        height: 92,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (!_hasValues(data)) {
      return _ChartEmptyState(key: Key(emptyKey), message: '$title暂无数据');
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ChartLegend(expenseColor: expenseColor, incomeColor: incomeColor),
        const SizedBox(height: 8),
        LayoutBuilder(
          builder: (context, constraints) {
            final availableWidth = constraints.hasBoundedWidth
                ? constraints.maxWidth
                : 360.0;
            final bucketWidth = data.unit == StatisticsBucketUnit.day
                ? 30.0
                : 54.0;
            final chartWidth = math
                .max(availableWidth, 56.0 + data.buckets.length * bucketWidth)
                .toDouble();
            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: chartWidth,
                height: 220,
                child: CustomPaint(
                  painter: _DualBarChartPainter(
                    buckets: data.buckets,
                    unit: data.unit,
                    expenseColor: expenseColor,
                    incomeColor: incomeColor,
                    gridColor: Theme.of(context).colorScheme.outlineVariant,
                    textColor: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 8),
        _TimeSeriesDetails(series: data, showAllBuckets: showAllBuckets),
      ],
    );
  }

  bool _hasValues(StatisticsTimeSeries data) {
    return data.buckets.any(
      (bucket) => bucket.expenseTotalCents > 0 || bucket.incomeTotalCents > 0,
    );
  }

  int _totalExpenses(StatisticsTimeSeries data) {
    return data.buckets.fold(
      0,
      (total, bucket) => total + bucket.expenseTotalCents,
    );
  }

  int _totalIncome(StatisticsTimeSeries data) {
    return data.buckets.fold(
      0,
      (total, bucket) => total + bucket.incomeTotalCents,
    );
  }
}

class StatisticsExpensePieChart extends StatelessWidget {
  const StatisticsExpensePieChart({
    required this.title,
    required this.range,
    required this.categories,
    required this.expenseTotalCents,
    required this.emptyKey,
    super.key,
  });

  final String title;
  final StatisticsDateRange range;
  final List<ExpenseCategoryStatistics> categories;
  final int expenseTotalCents;
  final String emptyKey;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final label =
        '$title，范围 ${range.startDateInclusive} 至 '
        '${range.endDateExclusive}，支出总额 '
        '${formatMoneyCents(expenseTotalCents)}，收入不计入分类';
    final colors = _pieColors(colorScheme);

    return Semantics(
      container: true,
      label: label,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: colorScheme.outlineVariant),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: categories.isEmpty || expenseTotalCents <= 0
              ? _ChartEmptyState(key: Key(emptyKey), message: '$title暂无数据')
              : Column(
                  children: [
                    SizedBox(
                      width: 188,
                      height: 188,
                      child: CustomPaint(
                        painter: _ExpensePieChartPainter(
                          categories: categories,
                          totalCents: expenseTotalCents,
                          colors: colors,
                        ),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _ChartLegend extends StatelessWidget {
  const _ChartLegend({required this.expenseColor, required this.incomeColor});

  final Color expenseColor;
  final Color incomeColor;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 16,
      runSpacing: 4,
      children: [
        _LegendItem(color: expenseColor, label: '支出'),
        _LegendItem(color: incomeColor, label: '收入'),
      ],
    );
  }
}

class _LegendItem extends StatelessWidget {
  const _LegendItem({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
          child: const SizedBox(width: 12, height: 12),
        ),
        const SizedBox(width: 6),
        Text(label),
      ],
    );
  }
}

class _TimeSeriesDetails extends StatelessWidget {
  const _TimeSeriesDetails({
    required this.series,
    required this.showAllBuckets,
  });

  final StatisticsTimeSeries series;
  final bool showAllBuckets;

  @override
  Widget build(BuildContext context) {
    final buckets = showAllBuckets
        ? series.buckets
        : series.buckets
              .where(
                (bucket) =>
                    bucket.expenseTotalCents > 0 || bucket.incomeTotalCents > 0,
              )
              .toList(growable: false);
    final outlineColor = Theme.of(context).colorScheme.outlineVariant;
    final textTheme = Theme.of(context).textTheme;
    return Table(
      key: const Key('statistics-time-series-table'),
      columnWidths: const {
        0: FlexColumnWidth(1.2),
        1: FlexColumnWidth(1),
        2: FlexColumnWidth(1),
      },
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      children: [
        TableRow(
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: outlineColor)),
          ),
          children: [
            _tableHeader('日期', textTheme),
            _tableHeader('支出', textTheme, alignment: TextAlign.right),
            _tableHeader('收入', textTheme, alignment: TextAlign.right),
          ],
        ),
        ...buckets.map((bucket) {
          final label = _bucketLabel(bucket.key, series.unit);
          final expense = formatMoneyCents(bucket.expenseTotalCents);
          final income = formatMoneyCents(bucket.incomeTotalCents);
          return TableRow(
            key: ValueKey('statistics-time-series-row-${bucket.key}'),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: outlineColor)),
            ),
            children: [
              Semantics(
                label: '$label，支出 $expense，收入 $income',
                child: _tableBody(label),
              ),
              _tableBody(expense, alignment: TextAlign.right),
              _tableBody(income, alignment: TextAlign.right),
            ],
          );
        }),
      ],
    );
  }
}

Widget _tableHeader(
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

Widget _tableBody(String text, {TextAlign alignment = TextAlign.left}) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Text(text, textAlign: alignment),
  );
}

class _ChartEmptyState extends StatelessWidget {
  const _ChartEmptyState({required this.message, super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    return SizedBox(height: 76, child: Center(child: Text(message)));
  }
}

class _DualBarChartPainter extends CustomPainter {
  _DualBarChartPainter({
    required this.buckets,
    required this.unit,
    required this.expenseColor,
    required this.incomeColor,
    required this.gridColor,
    required this.textColor,
  });

  final List<StatisticsTimeBucket> buckets;
  final StatisticsBucketUnit unit;
  final Color expenseColor;
  final Color incomeColor;
  final Color gridColor;
  final Color textColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (buckets.isEmpty) {
      return;
    }

    const rightPadding = 8.0;
    const topPadding = 10.0;
    const bottomPadding = 30.0;
    final maxValue = buckets.fold<int>(0, (current, bucket) {
      return math.max(
        current,
        math.max(bucket.expenseTotalCents, bucket.incomeTotalCents),
      );
    });
    final axisMax = maxValue == 0 ? 1 : maxValue;
    final axisLabels = List<String>.generate(
      5,
      (step) => _compactMoney((axisMax * step / 4).round()),
    );
    final leftPadding = math
        .max(44.0, _maxTextWidth(axisLabels) + 8.0)
        .toDouble();
    final chartWidth = size.width - leftPadding - rightPadding;
    final chartHeight = size.height - topPadding - bottomPadding;
    if (chartWidth <= 0 || chartHeight <= 0) {
      return;
    }

    final baseline = topPadding + chartHeight;
    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    final expensePaint = Paint()..color = expenseColor;
    final incomePaint = Paint()..color = incomeColor;

    for (var step = 0; step <= 4; step += 1) {
      final ratio = step / 4;
      final y = baseline - chartHeight * ratio;
      canvas.drawLine(
        Offset(leftPadding, y),
        Offset(size.width - rightPadding, y),
        gridPaint,
      );
      _paintText(
        canvas,
        axisLabels[step],
        Offset(0, y - 8),
        maxWidth: leftPadding - 5,
        alignment: TextAlign.right,
      );
    }

    final groupWidth = chartWidth / buckets.length;
    final barWidth = math.min(12.0, groupWidth * 0.28);
    for (var index = 0; index < buckets.length; index += 1) {
      final bucket = buckets[index];
      final centerX = leftPadding + groupWidth * (index + 0.5);
      final expenseHeight = chartHeight * bucket.expenseTotalCents / axisMax;
      final incomeHeight = chartHeight * bucket.incomeTotalCents / axisMax;
      canvas.drawRect(
        Rect.fromLTWH(
          centerX - barWidth - 2,
          baseline - expenseHeight,
          barWidth,
          expenseHeight,
        ),
        expensePaint,
      );
      canvas.drawRect(
        Rect.fromLTWH(
          centerX + 2,
          baseline - incomeHeight,
          barWidth,
          incomeHeight,
        ),
        incomePaint,
      );
      _paintText(
        canvas,
        _axisBucketLabel(bucket.key, unit),
        Offset(centerX - groupWidth / 2, baseline + 6),
        maxWidth: groupWidth,
        alignment: TextAlign.center,
        fontSize: unit == StatisticsBucketUnit.day ? 10 : 11,
      );
    }
  }

  double _maxTextWidth(Iterable<String> labels) {
    var maxWidth = 0.0;
    for (final label in labels) {
      final painter = TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(color: textColor, fontSize: 10),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout();
      maxWidth = math.max(maxWidth, painter.width).toDouble();
    }
    return maxWidth;
  }

  void _paintText(
    Canvas canvas,
    String text,
    Offset offset, {
    required double maxWidth,
    required TextAlign alignment,
    double fontSize = 10,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(color: textColor, fontSize: fontSize),
      ),
      textDirection: TextDirection.ltr,
      textAlign: alignment,
      maxLines: 1,
    )..layout(maxWidth: maxWidth);
    painter.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(covariant _DualBarChartPainter oldDelegate) {
    return oldDelegate.buckets != buckets ||
        oldDelegate.unit != unit ||
        oldDelegate.expenseColor != expenseColor ||
        oldDelegate.incomeColor != incomeColor ||
        oldDelegate.gridColor != gridColor ||
        oldDelegate.textColor != textColor;
  }
}

class _ExpensePieChartPainter extends CustomPainter {
  _ExpensePieChartPainter({
    required this.categories,
    required this.totalCents,
    required this.colors,
  });

  final List<ExpenseCategoryStatistics> categories;
  final int totalCents;
  final List<Color> colors;

  @override
  void paint(Canvas canvas, Size size) {
    final diameter = math.min(size.width, size.height);
    final rect = Rect.fromCenter(
      center: size.center(Offset.zero),
      width: diameter,
      height: diameter,
    );
    var startAngle = -math.pi / 2;
    for (var index = 0; index < categories.length; index += 1) {
      final category = categories[index];
      final sweepAngle = 2 * math.pi * category.amountCents / totalCents;
      final paint = Paint()..color = colors[index % colors.length];
      canvas.drawArc(rect, startAngle, sweepAngle, true, paint);
      startAngle += sweepAngle;
    }
  }

  @override
  bool shouldRepaint(covariant _ExpensePieChartPainter oldDelegate) {
    return oldDelegate.categories != categories ||
        oldDelegate.totalCents != totalCents ||
        oldDelegate.colors != colors;
  }
}

List<Color> _pieColors(ColorScheme colorScheme) {
  return [
    colorScheme.error,
    colorScheme.primary,
    colorScheme.tertiary,
    colorScheme.secondary,
    Colors.indigo,
    Colors.orange,
    Colors.pink,
    Colors.blueGrey,
  ];
}

String _bucketLabel(String key, StatisticsBucketUnit unit) {
  return switch (unit) {
    StatisticsBucketUnit.day => _dateLabel(key),
    StatisticsBucketUnit.month => _monthLabel(key),
    StatisticsBucketUnit.year => '$key年',
  };
}

String _axisBucketLabel(String key, StatisticsBucketUnit unit) {
  return switch (unit) {
    StatisticsBucketUnit.day =>
      key.length >= 10
          ? '${int.tryParse(key.substring(8, 10)) ?? key.substring(8, 10)}日'
          : key,
    StatisticsBucketUnit.month =>
      key.length >= 7
          ? '${int.tryParse(key.substring(5, 7)) ?? key.substring(5, 7)}月'
          : key,
    StatisticsBucketUnit.year => '$key年',
  };
}

String _dateLabel(String key) {
  final date = DateTime.tryParse(key);
  if (date == null) {
    return key;
  }
  return '${date.month}月${date.day}日';
}

String _monthLabel(String key) {
  if (key.length < 7) {
    return key;
  }
  final month = int.tryParse(key.substring(5, 7));
  return month == null ? key : '$month月';
}

String _compactMoney(int cents) {
  final yuan = cents ~/ 100;
  if (yuan >= 10000) {
    return '¥${(yuan / 10000).toStringAsFixed(1)}万';
  }
  if (yuan >= 1000) {
    return '¥${(yuan / 1000).toStringAsFixed(1)}k';
  }
  return formatMoneyCents(cents);
}

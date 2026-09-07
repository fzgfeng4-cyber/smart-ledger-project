import '../../shared/clock.dart';
import '../validation/transaction_validator.dart';
import 'statistics_bucket_unit.dart';

final class StatisticsDateRange {
  const StatisticsDateRange({
    required this.startDateInclusive,
    required this.endDateExclusive,
  });

  factory StatisticsDateRange.fromDates({
    required DateTime startInclusive,
    required DateTime endExclusive,
  }) {
    return StatisticsDateRange(
      startDateInclusive: formatLocalDate(startInclusive),
      endDateExclusive: formatLocalDate(endExclusive),
    );
  }

  factory StatisticsDateRange.month(DateTime month) {
    final start = DateTime(month.year, month.month);
    final end = DateTime(month.year, month.month + 1);
    return StatisticsDateRange.fromDates(
      startInclusive: start,
      endExclusive: end,
    );
  }

  factory StatisticsDateRange.year(DateTime year) {
    final start = DateTime(year.year);
    final end = DateTime(year.year + 1);
    return StatisticsDateRange.fromDates(
      startInclusive: start,
      endExclusive: end,
    );
  }

  void validate() {
    final start = TransactionValidator.parseTransactionDate(startDateInclusive);
    final end = TransactionValidator.parseTransactionDate(endDateExclusive);
    if (start == null || end == null || !start.isBefore(end)) {
      throw const TransactionValidationException('统计日期范围无效');
    }
  }

  List<StatisticsBucketRange> bucketRanges(StatisticsBucketUnit unit) {
    final start = _parseDate(startDateInclusive);
    final end = _parseDate(endDateExclusive);
    if (!start.isBefore(end)) {
      return const [];
    }

    final ranges = <StatisticsBucketRange>[];
    var cursor = _bucketStart(start, unit);
    while (cursor.isBefore(end)) {
      final next = _nextBucketStart(cursor, unit);
      final clippedStart = cursor.isBefore(start) ? start : cursor;
      final clippedEnd = next.isAfter(end) ? end : next;
      if (clippedStart.isBefore(clippedEnd)) {
        ranges.add(
          StatisticsBucketRange(
            key: _bucketKey(cursor, unit),
            startDateInclusive: formatLocalDate(clippedStart),
            endDateExclusive: formatLocalDate(clippedEnd),
          ),
        );
      }
      cursor = next;
    }
    return List.unmodifiable(ranges);
  }

  static String bucketKeyForDate(String localDate, StatisticsBucketUnit unit) {
    return _bucketKey(_parseDate(localDate), unit);
  }

  final String startDateInclusive;
  final String endDateExclusive;

  static DateTime _parseDate(String value) {
    final parsed = TransactionValidator.parseTransactionDate(value);
    if (parsed == null) {
      throw const TransactionValidationException('统计日期范围无效');
    }
    return parsed;
  }

  static DateTime _bucketStart(DateTime date, StatisticsBucketUnit unit) {
    return switch (unit) {
      StatisticsBucketUnit.day => DateTime(date.year, date.month, date.day),
      StatisticsBucketUnit.month => DateTime(date.year, date.month),
      StatisticsBucketUnit.year => DateTime(date.year),
    };
  }

  static DateTime _nextBucketStart(DateTime date, StatisticsBucketUnit unit) {
    return switch (unit) {
      StatisticsBucketUnit.day => DateTime(date.year, date.month, date.day + 1),
      StatisticsBucketUnit.month => DateTime(date.year, date.month + 1),
      StatisticsBucketUnit.year => DateTime(date.year + 1),
    };
  }

  static String _bucketKey(DateTime date, StatisticsBucketUnit unit) {
    final year = date.year.toString().padLeft(4, '0');
    return switch (unit) {
      StatisticsBucketUnit.day => formatLocalDate(date),
      StatisticsBucketUnit.month =>
        '$year-${date.month.toString().padLeft(2, '0')}',
      StatisticsBucketUnit.year => year,
    };
  }
}

final class StatisticsBucketRange {
  const StatisticsBucketRange({
    required this.key,
    required this.startDateInclusive,
    required this.endDateExclusive,
  });

  final String key;
  final String startDateInclusive;
  final String endDateExclusive;
}

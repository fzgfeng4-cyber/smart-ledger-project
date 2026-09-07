import 'statistics_bucket_unit.dart';
import 'statistics_date_range.dart';

export 'statistics_bucket_unit.dart';

final class StatisticsTimeBucket {
  const StatisticsTimeBucket({
    required this.key,
    required this.startDateInclusive,
    required this.endDateExclusive,
    required this.expenseTotalCents,
    required this.incomeTotalCents,
  });

  final String key;
  final String startDateInclusive;
  final String endDateExclusive;
  final int expenseTotalCents;
  final int incomeTotalCents;

  StatisticsTimeBucket copyWith({
    int? expenseTotalCents,
    int? incomeTotalCents,
  }) {
    return StatisticsTimeBucket(
      key: key,
      startDateInclusive: startDateInclusive,
      endDateExclusive: endDateExclusive,
      expenseTotalCents: expenseTotalCents ?? this.expenseTotalCents,
      incomeTotalCents: incomeTotalCents ?? this.incomeTotalCents,
    );
  }
}

final class StatisticsTimeSeries {
  StatisticsTimeSeries({
    required this.range,
    required this.unit,
    required Iterable<StatisticsTimeBucket> buckets,
  }) : buckets = _orderedBuckets(buckets);

  final StatisticsDateRange range;
  final StatisticsBucketUnit unit;
  final List<StatisticsTimeBucket> buckets;

  factory StatisticsTimeSeries.empty({
    required StatisticsDateRange range,
    required StatisticsBucketUnit unit,
  }) {
    return StatisticsTimeSeries(
      range: range,
      unit: unit,
      buckets: emptyBucketsFor(range, unit),
    );
  }

  static List<StatisticsTimeBucket> emptyBucketsFor(
    StatisticsDateRange range,
    StatisticsBucketUnit unit,
  ) {
    return List.unmodifiable(
      range
          .bucketRanges(unit)
          .map(
            (bucketRange) => StatisticsTimeBucket(
              key: bucketRange.key,
              startDateInclusive: bucketRange.startDateInclusive,
              endDateExclusive: bucketRange.endDateExclusive,
              expenseTotalCents: 0,
              incomeTotalCents: 0,
            ),
          ),
    );
  }

  static String bucketKeyForDate(String date, StatisticsBucketUnit unit) {
    return StatisticsDateRange.bucketKeyForDate(date, unit);
  }

  static List<StatisticsTimeBucket> _orderedBuckets(
    Iterable<StatisticsTimeBucket> buckets,
  ) {
    final copy = buckets.toList(growable: false);
    copy.sort((left, right) {
      final byStart = left.startDateInclusive.compareTo(
        right.startDateInclusive,
      );
      if (byStart != 0) {
        return byStart;
      }
      return left.key.compareTo(right.key);
    });
    return List.unmodifiable(copy);
  }
}

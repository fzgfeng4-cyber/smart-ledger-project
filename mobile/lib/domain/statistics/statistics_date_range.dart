import '../../shared/clock.dart';

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

  final String startDateInclusive;
  final String endDateExclusive;
}

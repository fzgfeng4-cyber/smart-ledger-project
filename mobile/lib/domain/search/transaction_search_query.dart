import '../../shared/clock.dart';
import '../categories/category_catalog.dart';

final class TransactionSearchQuery {
  const TransactionSearchQuery({
    required this.rawText,
    this.categoryCode,
    this.keyword,
    this.startDateInclusive,
    this.endDateExclusive,
  });

  final String rawText;
  final String? categoryCode;
  final String? keyword;
  final String? startDateInclusive;
  final String? endDateExclusive;

  bool get hasDateRange =>
      startDateInclusive != null && endDateExclusive != null;

  bool get isEmpty =>
      categoryCode == null &&
      keyword == null &&
      startDateInclusive == null &&
      endDateExclusive == null;
}

final class TransactionSearchQueryParser {
  const TransactionSearchQueryParser();

  TransactionSearchQuery parse(String text, {required DateTime today}) {
    final rawText = text.trim();
    if (rawText.isEmpty) {
      return const TransactionSearchQuery(rawText: '');
    }

    var remaining = rawText;
    String? startDateInclusive;
    String? endDateExclusive;

    final recentMatch = RegExp(r'^最近(\d{1,3})天').firstMatch(remaining);
    if (recentMatch != null) {
      final days = int.parse(recentMatch.group(1)!);
      if (days > 0) {
        final todayDate = _dateOnly(today);
        startDateInclusive = formatLocalDate(
          todayDate.subtract(Duration(days: days - 1)),
        );
        endDateExclusive = formatLocalDate(
          todayDate.add(const Duration(days: 1)),
        );
        remaining = remaining.substring(recentMatch.end).trim();
      }
    } else if (remaining.startsWith('本月')) {
      final todayDate = _dateOnly(today);
      final start = DateTime(todayDate.year, todayDate.month);
      final end = DateTime(todayDate.year, todayDate.month + 1);
      startDateInclusive = formatLocalDate(start);
      endDateExclusive = formatLocalDate(end);
      remaining = remaining.substring('本月'.length).trim();
    } else {
      final monthMatch = RegExp(r'^(\d{4})年(0?[1-9]|1[0-2])月')
          .firstMatch(remaining);
      if (monthMatch != null) {
        final year = int.parse(monthMatch.group(1)!);
        final month = int.parse(monthMatch.group(2)!);
        final start = DateTime(year, month);
        final end = DateTime(year, month + 1);
        startDateInclusive = formatLocalDate(start);
        endDateExclusive = formatLocalDate(end);
        remaining = remaining.substring(monthMatch.end).trim();
      }
    }

    final categoryMatch = CategoryCatalog.findSearchMatch(remaining);
    final categoryCode = categoryMatch?.category.code;
    final keyword = categoryMatch == null
        ? (remaining.isEmpty ? null : remaining)
        : remaining.replaceFirst(categoryMatch.keyword, '').trim();
    final normalizedKeyword = keyword == null || keyword.isEmpty
        ? null
        : keyword;
    return TransactionSearchQuery(
      rawText: rawText,
      categoryCode: categoryCode,
      keyword: normalizedKeyword,
      startDateInclusive: startDateInclusive,
      endDateExclusive: endDateExclusive,
    );
  }
}

DateTime _dateOnly(DateTime value) {
  return DateTime(value.year, value.month, value.day);
}

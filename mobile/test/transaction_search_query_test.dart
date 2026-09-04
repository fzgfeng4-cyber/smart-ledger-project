import 'package:flutter_test/flutter_test.dart';
import 'package:smartledger/domain/search/transaction_search_query.dart';

void main() {
  final parser = TransactionSearchQueryParser();
  final today = DateTime(2026, 8, 31, 10, 30);

  test('支持基础分类搜索', () {
    final query = parser.parse('加油', today: today);

    expect(query.rawText, '加油');
    expect(query.categoryCode, 'vehicle_fuel');
    expect(query.keyword, isNull);
    expect(query.hasDateRange, isFalse);
    expect(query.isEmpty, isFalse);
  });

  test('支持本月加油组合搜索', () {
    final query = parser.parse('本月加油', today: today);

    expect(query.categoryCode, 'vehicle_fuel');
    expect(query.startDateInclusive, '2026-08-01');
    expect(query.endDateExclusive, '2026-09-01');
    expect(query.hasDateRange, isTrue);
  });

  test('组合搜索保留分类以外的自由关键词', () {
    final query = parser.parse('本月餐饮星巴克', today: today);

    expect(query.categoryCode, 'dining');
    expect(query.keyword, '星巴克');
    expect(query.startDateInclusive, '2026-08-01');
    expect(query.endDateExclusive, '2026-09-01');
  });

  test('支持本月单独搜索', () {
    final query = parser.parse('本月', today: today);

    expect(query.categoryCode, isNull);
    expect(query.keyword, isNull);
    expect(query.startDateInclusive, '2026-08-01');
    expect(query.endDateExclusive, '2026-09-01');
    expect(query.hasDateRange, isTrue);
  });

  test('支持最近30天餐饮组合搜索', () {
    final query = parser.parse('最近30天餐饮', today: today);

    expect(query.categoryCode, 'dining');
    expect(query.startDateInclusive, '2026-08-02');
    expect(query.endDateExclusive, '2026-09-01');
  });

  test('支持月份搜索', () {
    final query = parser.parse('2026年8月', today: today);

    expect(query.categoryCode, isNull);
    expect(query.keyword, isNull);
    expect(query.startDateInclusive, '2026-08-01');
    expect(query.endDateExclusive, '2026-09-01');
  });

  test('支持未映射关键词回退为自由关键词', () {
    final query = parser.parse('超市', today: today);

    expect(query.categoryCode, isNull);
    expect(query.keyword, '超市');
    expect(query.hasDateRange, isFalse);
  });
}

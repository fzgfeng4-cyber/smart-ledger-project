import 'package:flutter_test/flutter_test.dart';
import 'package:smartledger/domain/search/transaction_search_query.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'test_support.dart';

void main() {
  sqfliteFfiInit();

  late TestLedgerFixture fixture;
  final parser = TransactionSearchQueryParser();

  setUpAll(() async {
    fixture = await TestLedgerFixture.create();
  });

  tearDownAll(() async {
    await fixture.dispose();
  });

  setUp(() async {
    await fixture.reset();
  });

  test('支持日期、分类和关键词组合筛选，并排除已删除账目', () async {
    final fuelCurrent = await fixture.seed(
      amountCents: 30000,
      category: 'vehicle_fuel',
      note: '中国石化',
      originalText: '中国石化300',
    );

    fixture.clock.set(DateTime(2026, 7, 31, 9));
    await fixture.seed(
      amountCents: 28000,
      category: 'vehicle_fuel',
      note: '中国石化',
      originalText: '中国石化280',
      transactionDate: '2026-07-31',
    );

    fixture.clock.set(DateTime(2026, 8, 31, 10, 30));
    final diningCurrent = await fixture.seed(
      amountCents: 1800,
      category: 'dining',
      note: '午饭',
      originalText: '午饭18元',
    );
    final groceryCurrent = await fixture.seed(
      amountCents: 4200,
      category: 'groceries_food',
      note: '超市购物',
      originalText: '超市购物42',
    );
    final deletedMedical = await fixture.seed(
      amountCents: 2000,
      category: 'medical',
      note: '挂号',
      originalText: '医院挂号20',
    );
    await fixture.repository.softDelete(deletedMedical.id);

    final monthFuelRows = await fixture.searchRepository.search(
      parser.parse('本月加油', today: fixture.controller.today),
    );
    expect(monthFuelRows, hasLength(1));
    expect(monthFuelRows.single.id, fuelCurrent.id);

    final monthRows = await fixture.searchRepository.search(
      parser.parse('2026年8月', today: fixture.controller.today),
    );
    expect(
      monthRows.map((entry) => entry.id).toSet(),
      equals(<int>{fuelCurrent.id, diningCurrent.id, groceryCurrent.id}),
    );
    expect(
      monthRows.map((entry) => entry.id),
      isNot(contains(deletedMedical.id)),
    );

    final monthOnlyRows = await fixture.searchRepository.search(
      parser.parse('本月', today: fixture.controller.today),
    );
    expect(
      monthOnlyRows.map((entry) => entry.id).toSet(),
      equals(<int>{fuelCurrent.id, diningCurrent.id, groceryCurrent.id}),
    );

    final keywordRows = await fixture.searchRepository.search(
      parser.parse('超市', today: fixture.controller.today),
    );
    expect(keywordRows, hasLength(1));
    expect(keywordRows.single.id, groceryCurrent.id);
  });
}

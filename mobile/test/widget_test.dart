import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartledger/app/smart_ledger_app.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'test_support.dart';

void main() {
  sqfliteFfiInit();

  late TestLedgerFixture fixture;
  setUpAll(() async {
    fixture = await TestLedgerFixture.create();
    await fixture.reset();
  });
  tearDownAll(() async {
    await fixture.dispose();
  });

  testWidgets('正式首页冒烟测试使用真实 Controller', (tester) async {
    await tester.pumpWidget(SmartLedgerApp(controller: fixture.controller));
    await tester.pumpAndSettle();

    expect(find.text('Smart Ledger'), findsOneWidget);
    expect(find.text('快速记账'), findsOneWidget);
    expect(find.byKey(const Key('quick-input')), findsOneWidget);
  });
}

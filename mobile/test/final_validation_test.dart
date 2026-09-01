import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:smartledger/data/repositories/transaction_repository.dart';
import 'package:smartledger/data/sqlite/app_database.dart';
import 'package:smartledger/data/sqlite/transaction_local_data_source.dart';
import 'package:smartledger/domain/models/ledger_transaction.dart';
import 'package:smartledger/domain/models/transaction_type.dart';
import 'package:smartledger/domain/parser/transaction_parser.dart';
import 'package:smartledger/domain/validation/transaction_validator.dart';
import 'package:smartledger/shared/clock.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  late Directory tempDir;
  late Database database;
  late MutableClock clock;
  late TransactionRepository repository;
  late TransactionParser parser;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp(
      'smart_ledger_final_validation_test_',
    );
    database = await AppDatabase.openAtPath(
      path.join(tempDir.path, 'smart-ledger.sqlite'),
      databaseFactory: databaseFactoryFfi,
    );
    clock = MutableClock(DateTime.utc(2026, 8, 31, 10, 30));
    repository = TransactionRepository(
      TransactionLocalDataSource(database),
      clock: clock,
    );
    parser = TransactionParser(clock: clock);
  });

  tearDown(() async {
    await database.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('中文样例通过 Parser、Classification、Repository 和 SQLite 全链路', () async {
    final cases = <_Sample>[
      _Sample('买菜35', 3500, TransactionType.expense, 'groceries_food'),
      _Sample('工资8000', 800000, TransactionType.income, 'salary'),
      _Sample('加油300', 30000, TransactionType.expense, 'vehicle_fuel'),
      _Sample('孩子奶粉260', 26000, TransactionType.expense, 'dining'),
    ];

    for (final sample in cases) {
      final parsed = parser.parse(sample.input);
      final draft = parsed.draft;
      expect(draft, isNotNull, reason: sample.input);
      expect(draft!.amountCents, sample.amountCents, reason: sample.input);
      expect(draft.type, sample.type, reason: sample.input);
      expect(draft.category, sample.category, reason: sample.input);

      final saved = await repository.create(
        NewLedgerTransaction(
          amountCents: draft.amountCents!,
          type: draft.type!,
          category: draft.category!,
          note: draft.note,
          originalText: draft.originalText,
          transactionDate: draft.transactionDate!,
        ),
      );
      expect(saved.originalText, sample.input);
    }

    expect(await repository.list(limit: 10), hasLength(cases.length));
    expect(await repository.monthIncomeCents(), 800000);
    expect(await repository.monthExpenseCents(), 59500);
    expect(await repository.todayExpenseCents(), 59500);
  });

  test('边界金额、备注、月初月末和跨年统计符合 V1 规则', () async {
    await expectLater(
      repository.create(_newTransaction(amountCents: 0)),
      throwsA(isA<TransactionValidationException>()),
    );
    await expectLater(
      repository.create(
        _newTransaction(note: List<String>.filled(201, '长').join()),
      ),
      throwsA(isA<TransactionValidationException>()),
    );

    final emptyNote = await repository.create(
      _newTransaction(note: '   ', transactionDate: '2026-07-31'),
    );
    expect(emptyNote.note, isNull);

    await repository.create(
      _newTransaction(
        amountCents: 1000,
        originalText: '月初账目10',
        transactionDate: '2026-08-01',
      ),
    );
    await repository.create(
      _newTransaction(
        amountCents: 2000,
        originalText: '月末账目20',
        transactionDate: '2026-08-31',
      ),
    );
    await repository.create(
      _newTransaction(
        amountCents: 3000,
        originalText: '上月账目30',
        transactionDate: '2026-07-31',
      ),
    );

    clock.set(DateTime.utc(2027, 1, 2, 10, 30));
    await repository.create(
      _newTransaction(
        amountCents: 4000,
        originalText: '跨年账目40',
        transactionDate: '2027-01-01',
      ),
    );

    clock.set(DateTime.utc(2026, 8, 31, 10, 30));
    expect(await repository.monthExpenseCents(), 3000);
    expect(await repository.todayExpenseCents(), 2000);
    expect(parser.parse('999999999999999999999999999999元工资').draft, isNotNull);
    expect(
      parser
          .parse('999999999999999999999999999999元工资')
          .hasIssue('INVALID_AMOUNT'),
      isTrue,
    );
  });
}

final class _Sample {
  const _Sample(this.input, this.amountCents, this.type, this.category);

  final String input;
  final int amountCents;
  final TransactionType type;
  final String category;
}

NewLedgerTransaction _newTransaction({
  int amountCents = 3500,
  String? note = '测试',
  String originalText = '测试账目35',
  String transactionDate = '2026-08-31',
}) {
  return NewLedgerTransaction(
    amountCents: amountCents,
    type: TransactionType.expense,
    category: 'groceries_food',
    note: note,
    originalText: originalText,
    transactionDate: transactionDate,
  );
}

final class MutableClock implements Clock {
  MutableClock(this._now);

  DateTime _now;

  void set(DateTime now) {
    _now = now;
  }

  @override
  DateTime now() => _now;
}

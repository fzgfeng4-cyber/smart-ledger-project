import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:smartledger/data/import/import_coordinator.dart';
import 'package:smartledger/data/import/import_file_picker.dart';
import 'package:smartledger/data/import/import_fingerprint.dart';
import 'package:smartledger/data/sqlite/database_schema.dart';
import 'package:smartledger/domain/import/import_contract.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'test_support.dart';

void main() {
  sqfliteFfiInit();

  late TestLedgerFixture fixture;

  setUpAll(() async {
    fixture = await TestLedgerFixture.create();
  });

  setUp(() async {
    await fixture.reset();
  });

  tearDownAll(() async {
    await fixture.dispose();
  });

  test('取消选择不解析也不改账', () async {
    final picker = _FakeImportFilePicker([null]);
    final coordinator = ImportCoordinator(
      repository: fixture.repository,
      filePicker: picker,
    );

    final result = await coordinator.pickAndParse(ImportSourceType.wechatCsv);

    expect(result, isNull);
    expect(picker.calls, 1);
    expect(await fixture.repository.list(), isEmpty);
  });

  test('解析保留来源、统计和错误行，并在确认后走批量保存', () async {
    final picker = _FakeImportFilePicker([_pickedFile()]);
    final coordinator = ImportCoordinator(
      repository: fixture.repository,
      filePicker: picker,
    );

    final firstParse = await coordinator.pickAndParse(
      ImportSourceType.alipayCsv,
    );
    expect(firstParse, isNotNull);
    expect(firstParse!.source.type, ImportSourceType.alipayCsv);
    expect(firstParse.source.fileName, '支付宝账单.csv');
    expect(firstParse.rows, hasLength(2));
    expect(firstParse.candidateRows, hasLength(2));
    expect(firstParse.blockingRows, hasLength(1));
    expect(firstParse.rows.last.rawRow.lineNumber, 4);
    expect(await fixture.repository.list(), isEmpty);

    final candidate = firstParse.candidateRows
        .where((row) => !row.hasBlockingIssues)
        .single
        .toNewLedgerTransaction();
    expect(candidate, isNotNull);
    await fixture.repository.create(candidate!);

    final duplicateBatch = await coordinator.parsePickedFile(
      ImportSourceType.alipayCsv,
      _pickedFile(),
    );
    final duplicateRow = duplicateBatch.candidateRows
        .where((row) => !row.hasBlockingIssues)
        .single;
    expect(duplicateRow.duplicateNotice, isNotNull);
    expect(duplicateRow.issues, contains(isA<ImportIssue>()));
    expect(
      duplicateRow.issues.any(
        (issue) => issue.code == ImportIssueCodes.duplicateCandidate,
      ),
      isTrue,
    );

    final readyBatch = duplicateBatch.exclude(4).confirm(3);
    expect(readyBatch.canSubmit, isTrue);
    final saved = await coordinator.saveBatch(
      readyBatch,
      readyBatch.transactionsToSave,
    );

    expect(saved, hasLength(1));
    expect(await fixture.repository.list(), hasLength(2));
  });

  test('确认前调用保存会被拒绝且数据库保持不变', () async {
    final coordinator = ImportCoordinator(repository: fixture.repository);
    final batch = await coordinator.parsePickedFile(
      ImportSourceType.wechatCsv,
      _pickedFile(source: ImportSourceType.wechatCsv),
    );

    await expectLater(
      coordinator.saveBatch(batch, batch.transactionsToSave),
      throwsA(isA<ImportCoordinatorException>()),
    );
    expect(await fixture.repository.list(), isEmpty);
  });

  test('同一导入文件内的重复账目都会显示重复提示', () async {
    final coordinator = ImportCoordinator(repository: fixture.repository);
    final batch = await coordinator.parsePickedFile(
      ImportSourceType.alipayCsv,
      _duplicatePickedFile(),
    );

    final candidates = batch.candidateRows;
    expect(candidates, hasLength(2));
    expect(candidates.every((row) => row.duplicateNotice != null), isTrue);
    expect(
      candidates.every((row) => row.duplicateNotice!.message.contains('当前文件第')),
      isTrue,
    );
    expect(batch.canSubmit, isFalse);
    expect(await fixture.repository.list(), isEmpty);
  });

  test('同一导入文件确认保存两次时持久化幂等且不新增重复账目', () async {
    final coordinator = ImportCoordinator(repository: fixture.repository);
    final batch = await coordinator.parsePickedFile(
      ImportSourceType.alipayCsv,
      _pickedFile(),
    );
    final readyBatch = batch.exclude(4).confirm(3);

    final firstSaved = await coordinator.saveBatch(
      readyBatch,
      readyBatch.transactionsToSave,
    );
    expect(firstSaved, hasLength(1));
    expect(await fixture.repository.list(), hasLength(1));

    await expectLater(
      coordinator.saveBatch(readyBatch, readyBatch.transactionsToSave),
      throwsA(
        isA<ImportCoordinatorException>().having(
          (error) => error.message,
          'message',
          '这份账单文件已经导入过，未重复写入。',
        ),
      ),
    );
    expect(await fixture.repository.list(), hasLength(1));
    expect(
      await fixture.database.query(DatabaseSchema.importBatchesTable),
      hasLength(1),
    );
  });

  test('同一账单带不带 UTF-8 BOM 都使用同一导入指纹', () async {
    final coordinator = ImportCoordinator(repository: fixture.repository);
    final original = _pickedFile();
    final bomText = '\uFEFF${utf8.decode(original.bytes)}';
    final first = await coordinator.parsePickedFile(
      ImportSourceType.alipayCsv,
      original,
    );
    final second = await coordinator.parsePickedFile(
      ImportSourceType.alipayCsv,
      PickedImportFile(fileName: '支付宝账单-BOM.csv', bytes: utf8.encode(bomText)),
    );

    expect(
      importContentFingerprint(
        source: ImportSourceType.alipayCsv,
        originalText: utf8.decode(original.bytes),
      ),
      importContentFingerprint(
        source: ImportSourceType.alipayCsv,
        originalText: bomText,
      ),
    );

    final firstReady = first.exclude(4).confirm(3);
    await coordinator.saveBatch(firstReady, firstReady.transactionsToSave);
    final secondReady = second.exclude(4).confirm(3);

    await expectLater(
      coordinator.saveBatch(secondReady, secondReady.transactionsToSave),
      throwsA(
        isA<ImportCoordinatorException>().having(
          (error) => error.message,
          'message',
          '这份账单文件已经导入过，未重复写入。',
        ),
      ),
    );
    expect(await fixture.repository.list(), hasLength(1));
  });

  test('保存时拒绝不属于当前确认批次的交易', () async {
    final coordinator = ImportCoordinator(repository: fixture.repository);
    final batch = await coordinator.parsePickedFile(
      ImportSourceType.alipayCsv,
      _pickedFile(),
    );
    final ready = batch.exclude(4).confirm(3);
    final unrelated = ready.transactionsToSave.single.copyWith(
      amountCents: 3600,
    );

    await expectLater(
      coordinator.saveBatch(ready, [unrelated]),
      throwsA(
        isA<ImportCoordinatorException>().having(
          (error) => error.message,
          'message',
          '导入确认内容已变化，请返回当前导入批次重新确认后再保存。',
        ),
      ),
    );
    expect(await fixture.repository.list(), isEmpty);
  });

  test('非 CSV 文件和空文件显示可重试错误', () async {
    final coordinator = ImportCoordinator(repository: fixture.repository);

    await expectLater(
      coordinator.parsePickedFile(
        ImportSourceType.wechatCsv,
        PickedImportFile(fileName: '账单.txt', bytes: utf8.encode('内容')),
      ),
      throwsA(
        isA<ImportCoordinatorException>().having(
          (error) => error.message,
          'message',
          '请选择 CSV 文件。',
        ),
      ),
    );
    await expectLater(
      coordinator.parsePickedFile(
        ImportSourceType.wechatCsv,
        PickedImportFile(fileName: '账单.csv', bytes: const []),
      ),
      throwsA(
        isA<ImportCoordinatorException>().having(
          (error) => error.message,
          'message',
          '所选 CSV 文件为空，无法解析账单。',
        ),
      ),
    );
    expect(await fixture.repository.list(), isEmpty);
  });

  test('超过 CSV 文件大小上限时拒绝解析', () async {
    final coordinator = ImportCoordinator(repository: fixture.repository);
    final oversized = PickedImportFile(
      fileName: '超大账单.csv',
      bytes: List<int>.filled(ImportLimits.maxFileBytes + 1, 32),
    );

    await expectLater(
      coordinator.parsePickedFile(ImportSourceType.wechatCsv, oversized),
      throwsA(
        isA<ImportCoordinatorException>().having(
          (error) => error.message,
          'message',
          'CSV 文件超过 10 MB 大小上限，请拆分账单后重试。',
        ),
      ),
    );
    expect(await fixture.repository.list(), isEmpty);
  });
}

final class _FakeImportFilePicker implements ImportFilePicker {
  _FakeImportFilePicker(Iterable<PickedImportFile?> responses)
    : _responses = [...responses];

  final List<PickedImportFile?> _responses;
  int calls = 0;

  @override
  Future<PickedImportFile?> pickCsv() async {
    calls += 1;
    if (_responses.isEmpty) {
      return null;
    }
    return _responses.removeAt(0);
  }
}

PickedImportFile _pickedFile({
  ImportSourceType source = ImportSourceType.alipayCsv,
}) {
  final text = source == ImportSourceType.alipayCsv
      ? '''支付宝交易记录明细
交易时间,交易分类,收/支,金额,交易对方,商品说明,交易订单号,资金状态
2026-08-31 12:30:00,餐饮,支出,35.00,星巴克,咖啡,ORDER-1,交易成功
2026-08-31 12:31:00,餐饮,支出,12.345,星巴克,咖啡,BAD-1,交易成功
'''
      : '''交易时间,收支,交易对方,金额(元),当前状态
2026-08-31,支出,菜市场,35.00,交易成功
''';
  return PickedImportFile(
    fileName: source == ImportSourceType.alipayCsv ? '支付宝账单.csv' : '微信账单.csv',
    bytes: utf8.encode(text),
  );
}

PickedImportFile _duplicatePickedFile() {
  const text = '''支付宝交易记录明细
交易时间,交易分类,收/支,金额,交易对方,商品说明,交易订单号,资金状态
2026-08-31 12:30:00,餐饮,支出,35.00,星巴克,咖啡,ORDER-1,交易成功
2026-08-31 12:30:00,餐饮,支出,35.00,星巴克,咖啡,ORDER-2,交易成功
''';
  return PickedImportFile(fileName: '支付宝重复账单.csv', bytes: utf8.encode(text));
}

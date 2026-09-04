import '../../domain/import/alipay_csv_parser.dart';
import '../../domain/import/import_contract.dart';
import '../../domain/import/wechat_csv_parser.dart';
import '../../domain/models/ledger_transaction.dart';
import '../../domain/validation/transaction_validator.dart';
import '../../shared/clock.dart';
import '../repositories/transaction_repository.dart';
import 'import_file_picker.dart';
import 'import_fingerprint.dart';

final class ImportCoordinator {
  ImportCoordinator({
    required this.repository,
    ImportFilePicker? filePicker,
    WechatCsvParser? wechatParser,
    AlipayCsvParser? alipayParser,
    Clock? clock,
  }) : filePicker = filePicker ?? const MethodChannelImportFilePicker(),
       _wechatParser =
           wechatParser ?? WechatCsvParser(clock: clock ?? const SystemClock()),
       _alipayParser =
           alipayParser ?? AlipayCsvParser(clock: clock ?? const SystemClock());

  final TransactionRepository repository;
  final ImportFilePicker filePicker;
  final WechatCsvParser _wechatParser;
  final AlipayCsvParser _alipayParser;

  Future<ImportDraftBatch?> pickAndParse(ImportSourceType source) async {
    _ensureSupportedSource(source);
    final file = await filePicker.pickCsv();
    if (file == null) {
      return null;
    }
    return parsePickedFile(source, file);
  }

  Future<ImportDraftBatch> parsePickedFile(
    ImportSourceType source,
    PickedImportFile file,
  ) async {
    _ensureSupportedSource(source);
    final fileName = file.fileName.trim();
    if (fileName.isEmpty) {
      throw const ImportCoordinatorException('未读取到所选文件名。');
    }
    if (!_looksLikeCsv(fileName)) {
      throw const ImportCoordinatorException('请选择 CSV 文件。');
    }
    if (file.bytes.isEmpty) {
      throw const ImportCoordinatorException('所选 CSV 文件为空，无法解析账单。');
    }
    try {
      ImportLimits.ensureBytesWithinLimit(file.bytes.length);
    } on ImportInputLimitException catch (error) {
      throw ImportCoordinatorException(error.message, cause: error);
    }

    final parsed = _parse(source, file.bytes, fileName);
    return _attachDuplicateNotices(parsed);
  }

  Future<ImportDraftBatch> recheckDuplicates(ImportDraftBatch batch) {
    return _attachDuplicateNotices(batch);
  }

  Future<List<LedgerTransaction>> saveBatch(
    ImportDraftBatch batch,
    Iterable<NewLedgerTransaction> transactions,
  ) async {
    if (!batch.canSubmit) {
      throw const ImportCoordinatorException('仍有未确认或有问题的导入行，请先处理后再保存。');
    }
    final entries = transactions.toList(growable: false);
    if (entries.isEmpty) {
      throw const ImportCoordinatorException('没有可保存的导入账目。');
    }
    if (!_sameTransactions(entries, batch.transactionsToSave)) {
      throw const ImportCoordinatorException('导入确认内容已变化，请返回当前导入批次重新确认后再保存。');
    }
    try {
      return await repository.createImportedBatch(
        source: batch.source.type.code,
        fingerprint: importContentFingerprint(
          source: batch.source.type,
          originalText: batch.originalText,
        ),
        fileName: batch.source.fileName,
        inputs: entries,
      );
    } on ImportBatchAlreadyExistsException {
      throw const ImportCoordinatorException('这份账单文件已经导入过，未重复写入。');
    }
  }

  ImportDraftBatch _parse(
    ImportSourceType source,
    List<int> bytes,
    String fileName,
  ) {
    try {
      return switch (source) {
        ImportSourceType.wechatCsv => _wechatParser.parseBytes(
          bytes,
          fileName: fileName,
        ),
        ImportSourceType.alipayCsv => _alipayParser.parseBytes(
          bytes,
          fileName: fileName,
        ),
        ImportSourceType.otherCsv || ImportSourceType.unknown =>
          throw const ImportCoordinatorException('请选择微信或支付宝账单来源。'),
      };
    } on ImportCoordinatorException {
      rethrow;
    } on ImportInputLimitException catch (error) {
      throw ImportCoordinatorException(error.message, cause: error);
    } on FormatException catch (error) {
      throw ImportCoordinatorException(
        'CSV 文件编码无法识别，请导出 UTF-8 CSV 后重试。',
        cause: error,
      );
    } on Object catch (error) {
      throw ImportCoordinatorException('CSV 文件解析失败，请重试。', cause: error);
    }
  }

  Future<ImportDraftBatch> _attachDuplicateNotices(
    ImportDraftBatch batch,
  ) async {
    final transactionsByKey = <String, List<int>>{};
    for (final row in batch.rows) {
      final transaction = row.toNewLedgerTransaction();
      if (transaction == null) {
        continue;
      }
      transactionsByKey
          .putIfAbsent(_matchKey(transaction), () => <int>[])
          .add(row.rawRow.lineNumber);
    }

    final rows = <ImportDraftRow>[];
    for (final row in batch.rows) {
      final transaction = row.toNewLedgerTransaction();
      if (transaction == null) {
        rows.add(row);
        continue;
      }

      LedgerTransaction? matching;
      try {
        matching = await repository.findLatestDuplicateCandidate(transaction);
      } on TransactionValidationException {
        rows.add(
          _withBatchDuplicateNotice(row, transaction, transactionsByKey),
        );
        continue;
      }

      rows.add(
        _withDuplicateNotice(
          row: row,
          transaction: transaction,
          matching: matching,
          transactionsByKey: transactionsByKey,
        ),
      );
    }

    return ImportDraftBatch(
      source: batch.source,
      originalText: batch.originalText,
      rows: rows,
    );
  }

  ImportDraftRow _withBatchDuplicateNotice(
    ImportDraftRow row,
    NewLedgerTransaction transaction,
    Map<String, List<int>> transactionsByKey,
  ) {
    return _withDuplicateNotice(
      row: row,
      transaction: transaction,
      transactionsByKey: transactionsByKey,
    );
  }

  ImportDraftRow _withDuplicateNotice({
    required ImportDraftRow row,
    required NewLedgerTransaction transaction,
    required Map<String, List<int>> transactionsByKey,
    LedgerTransaction? matching,
  }) {
    final key = _matchKey(transaction);
    final batchMatches = (transactionsByKey[key] ?? const <int>[])
        .where((lineNumber) => lineNumber != row.rawRow.lineNumber)
        .toList(growable: false);
    if (matching == null && batchMatches.isEmpty) {
      return row.copyWith(duplicateNotice: null);
    }

    final messages = <String>[
      if (matching != null) '疑似与已有账目 #${matching.id} 重复（日期、金额、收支和分类相同）',
      if (batchMatches.isNotEmpty)
        '疑似与当前文件第 ${batchMatches.join('、')} 行重复（日期、金额、收支和分类相同）',
    ];
    return row.copyWith(
      duplicateNotice: ImportDuplicateNotice(
        message: '${messages.join('；')}，请确认是否仍要导入。',
        matchingTransactionId: matching?.id,
        matchKey: key,
      ),
    );
  }

  void _ensureSupportedSource(ImportSourceType source) {
    if (source != ImportSourceType.wechatCsv &&
        source != ImportSourceType.alipayCsv) {
      throw const ImportCoordinatorException('请选择微信或支付宝账单来源。');
    }
  }

  bool _looksLikeCsv(String fileName) {
    final normalized = fileName.toLowerCase();
    return !normalized.contains('.') || normalized.endsWith('.csv');
  }

  String _matchKey(NewLedgerTransaction transaction) {
    return '${transaction.transactionDate}|${transaction.amountCents}|'
        '${transaction.type.code}|${transaction.category}';
  }

  bool _sameTransactions(
    List<NewLedgerTransaction> actual,
    List<NewLedgerTransaction> expected,
  ) {
    if (actual.length != expected.length) {
      return false;
    }
    for (var index = 0; index < actual.length; index += 1) {
      final left = actual[index];
      final right = expected[index];
      if (left.amountCents != right.amountCents ||
          left.type != right.type ||
          left.category != right.category ||
          left.note != right.note ||
          left.originalText != right.originalText ||
          left.transactionDate != right.transactionDate) {
        return false;
      }
    }
    return true;
  }
}

final class ImportCoordinatorException implements Exception {
  const ImportCoordinatorException(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() => message;
}

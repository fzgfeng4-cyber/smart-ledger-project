import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

import '../budget/budget_local_data_source.dart';
import '../../domain/budget/budget.dart';
import '../../domain/budget/budget_validator.dart';
import '../../domain/categories/category_catalog.dart';
import '../../domain/import/import_batch_record.dart';
import '../../domain/models/ledger_transaction.dart';
import '../../domain/models/transaction_type.dart';
import '../../domain/validation/transaction_validator.dart';
import '../../shared/clock.dart';
import '../sqlite/database_schema.dart';
import '../sqlite/transaction_local_data_source.dart';

const _requiredBackupKeys = <String>{
  'backup_version',
  'app_version',
  'database_version',
  'created_at',
  'transactions',
};

const _currentBackupKeys = <String>{
  ..._requiredBackupKeys,
  'budgets',
  'import_batches',
};

const _requiredTransactionKeys = <String>{
  'id',
  'amount_cents',
  'type',
  'category',
  'note',
  'original_text',
  'transaction_date',
  'created_at',
  'updated_at',
  'deleted_at',
};

const _requiredBudgetKeys = <String>{
  'id',
  'category_code',
  'month',
  'amount_cents',
  'enabled',
  'created_at',
  'updated_at',
};

const _requiredImportBatchKeys = <String>{
  'id',
  'source',
  'fingerprint',
  'file_name',
  'transaction_count',
  'imported_at',
};

final class BackupException implements Exception {
  const BackupException(this.message);

  final String message;

  @override
  String toString() => 'BackupException: $message';
}

final class BackupExportResult {
  const BackupExportResult({
    required this.filePath,
    required this.transactionCount,
    required this.deletedCount,
    required this.budgetCount,
    required this.createdAt,
  });

  final String filePath;
  final int transactionCount;
  final int deletedCount;
  final int budgetCount;
  final DateTime createdAt;

  String get fileName => path.basename(filePath);
}

final class BackupImportResult {
  const BackupImportResult({
    required this.filePath,
    required this.transactionCount,
    required this.deletedCount,
    required this.budgetCount,
  });

  final String filePath;
  final int transactionCount;
  final int deletedCount;
  final int budgetCount;
}

final class BackupFileInfo {
  const BackupFileInfo({
    required this.filePath,
    required this.modifiedAt,
    required this.sizeBytes,
  });

  final String filePath;
  final DateTime modifiedAt;
  final int sizeBytes;

  String get fileName => path.basename(filePath);
}

final class BackupService {
  BackupService({
    required this.dataSource,
    required this.budgetDataSource,
    Clock? clock,
    this.backupDirectoryPath,
  }) : _clock = clock ?? const SystemClock();

  static const backupVersion = 2;
  static const legacyBackupVersion = 1;
  static const appVersion = '2.6.0+2';

  final TransactionLocalDataSource dataSource;
  final BudgetLocalDataSource budgetDataSource;
  final Clock _clock;
  final String? backupDirectoryPath;

  Future<BackupExportResult> exportBackup() async {
    final entries = await dataSource.listAllForBackup();
    final budgets = await budgetDataSource.listAllForBackup();
    final importBatches = await dataSource.listAllImportBatches();
    final createdAt = _clock.now().toUtc();
    final payload = <String, Object?>{
      'backup_version': backupVersion,
      'app_version': appVersion,
      'database_version': DatabaseSchema.version,
      'created_at': createdAt.toIso8601String(),
      'transactions': entries.map((entry) => entry.toMap()).toList(),
      'budgets': budgets.map((budget) => budget.toMap()).toList(),
      'import_batches': importBatches.map((batch) => batch.toMap()).toList(),
    };

    final directory = await _resolveBackupDirectory();
    await directory.create(recursive: true);
    final filePath = await _nextBackupPath(directory.path, createdAt);
    final file = File(filePath);
    final temporaryFile = File('$filePath.tmp');

    try {
      await temporaryFile.writeAsString(
        const JsonEncoder.withIndent('  ').convert(payload),
        encoding: utf8,
        flush: true,
      );
      await temporaryFile.rename(file.path);
    } catch (error) {
      if (await temporaryFile.exists()) {
        await temporaryFile.delete();
      }
      throw BackupException('备份文件写入失败: $error');
    }

    return BackupExportResult(
      filePath: file.path,
      transactionCount: entries.length,
      deletedCount: entries.where((entry) => entry.isDeleted).length,
      budgetCount: budgets.length,
      createdAt: createdAt,
    );
  }

  Future<BackupImportResult> importBackup(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw const BackupException('备份文件不存在。');
    }

    late final String rawJson;
    try {
      rawJson = await file.readAsString(encoding: utf8);
    } on Object {
      throw const BackupException('备份文件读取失败。');
    }
    final parsed = _parseAndValidate(rawJson);
    try {
      await dataSource.replaceAllForBackup(
        parsed.transactions,
        budgets: parsed.budgets,
        importBatches: parsed.importBatches,
      );
    } on Object catch (error) {
      throw BackupException('恢复备份失败: $error');
    }

    return BackupImportResult(
      filePath: file.path,
      transactionCount: parsed.transactions.length,
      deletedCount: parsed.transactions
          .where((entry) => entry.isDeleted)
          .length,
      budgetCount: parsed.budgets.length,
    );
  }

  Future<List<BackupFileInfo>> listBackups() async {
    final directory = await _resolveBackupDirectory();
    if (!await directory.exists()) {
      return const [];
    }

    final files = <BackupFileInfo>[];
    await for (final entity in directory.list()) {
      if (entity is! File ||
          path.extension(entity.path).toLowerCase() != '.json') {
        continue;
      }
      final stat = await entity.stat();
      files.add(
        BackupFileInfo(
          filePath: entity.path,
          modifiedAt: stat.modified,
          sizeBytes: stat.size,
        ),
      );
    }
    files.sort((left, right) => right.modifiedAt.compareTo(left.modifiedAt));
    return files;
  }

  Future<Directory> _resolveBackupDirectory() async {
    final configuredPath = backupDirectoryPath;
    if (configuredPath != null && configuredPath.trim().isNotEmpty) {
      return Directory(configuredPath);
    }
    return Directory(path.join(await getDatabasesPath(), 'backups'));
  }

  Future<String> _nextBackupPath(
    String directoryPath,
    DateTime createdAt,
  ) async {
    final stamp = _formatFileStamp(createdAt);
    var suffix = 0;
    while (true) {
      final suffixText = suffix == 0 ? '' : '-$suffix';
      final candidate = path.join(
        directoryPath,
        'smart-ledger-backup-$stamp$suffixText.json',
      );
      if (!await File(candidate).exists() &&
          !await File('$candidate.tmp').exists()) {
        return candidate;
      }
      suffix += 1;
    }
  }

  _ParsedBackup _parseAndValidate(String rawJson) {
    final decoded = _decodeJson(rawJson);
    final backup = _asMap(decoded, '备份根对象');

    final backupVersionValue = _readInt(backup, 'backup_version');
    if (backupVersionValue != legacyBackupVersion &&
        backupVersionValue != backupVersion) {
      throw BackupException(
        '不支持的备份版本: $backupVersionValue，支持版本为 '
        '$legacyBackupVersion 和 $backupVersion。',
      );
    }
    _requireExactKeys(
      backup,
      backupVersionValue == legacyBackupVersion
          ? _requiredBackupKeys
          : _currentBackupKeys,
      '备份根对象',
    );

    final databaseVersion = _readInt(backup, 'database_version');
    final expectedDatabaseVersion = backupVersionValue == legacyBackupVersion
        ? 1
        : DatabaseSchema.version;
    if (databaseVersion != expectedDatabaseVersion) {
      throw BackupException(
        '备份版本 $backupVersionValue 与数据库版本 '
        '$databaseVersion 不匹配，期望数据库版本为 $expectedDatabaseVersion。',
      );
    }

    final appVersion = _readString(backup, 'app_version');
    if (appVersion.trim().isEmpty) {
      throw const BackupException('备份 app_version 不能为空。');
    }
    _readTimestamp(backup, 'created_at');

    final rawTransactions = backup['transactions'];
    if (rawTransactions is! List<Object?>) {
      throw const BackupException('备份 transactions 必须是数组。');
    }

    final ids = <int>{};
    final entries = <LedgerTransaction>[];
    for (var index = 0; index < rawTransactions.length; index += 1) {
      final map = _asMap(rawTransactions[index], 'transactions[$index]');
      _requireExactKeys(map, _requiredTransactionKeys, 'transactions[$index]');
      final entry = _parseTransaction(
        map,
        index,
        allowLegacyValues: backupVersionValue == legacyBackupVersion,
      );
      if (!ids.add(entry.id)) {
        throw BackupException('备份包含重复 id: ${entry.id}。');
      }
      entries.add(entry);
    }

    final budgets = backupVersionValue == legacyBackupVersion
        ? const <Budget>[]
        : _parseBudgets(backup['budgets']);
    final importBatches = backupVersionValue == legacyBackupVersion
        ? const <ImportBatchRecord>[]
        : _parseImportBatches(backup['import_batches']);
    return _ParsedBackup(
      transactions: entries,
      budgets: budgets,
      importBatches: importBatches,
    );
  }

  List<ImportBatchRecord> _parseImportBatches(Object? rawImportBatches) {
    if (rawImportBatches is! List<Object?>) {
      throw const BackupException('备份 import_batches 必须是数组。');
    }

    final ids = <int>{};
    final identities = <String>{};
    final batches = <ImportBatchRecord>[];
    for (var index = 0; index < rawImportBatches.length; index += 1) {
      final map = _asMap(rawImportBatches[index], 'import_batches[$index]');
      _requireExactKeys(
        map,
        _requiredImportBatchKeys,
        'import_batches[$index]',
      );

      final prefix = 'import_batches[$index]';
      final id = _readInt(map, 'id');
      final source = _readString(map, 'source');
      final fingerprint = _readString(map, 'fingerprint');
      final fileName = _readString(map, 'file_name');
      final transactionCount = _readInt(map, 'transaction_count');
      final importedAt = _readTimestamp(map, 'imported_at');
      if (id <= 0) {
        throw BackupException('$prefix.id 必须是正整数。');
      }
      if (!ids.add(id)) {
        throw BackupException('备份包含重复导入批次 id: $id。');
      }
      if (source != 'wechat_csv' && source != 'alipay_csv') {
        throw BackupException('$prefix.source 不是支持的导入来源。');
      }
      if (fingerprint.trim().isEmpty || fingerprint.length > 200) {
        throw BackupException('$prefix.fingerprint 长度无效。');
      }
      if (fileName.trim().isEmpty || fileName.length > 200) {
        throw BackupException('$prefix.file_name 长度无效。');
      }
      if (transactionCount <= 0) {
        throw BackupException('$prefix.transaction_count 必须是正整数。');
      }
      if (!identities.add('$source|$fingerprint')) {
        throw BackupException('$prefix 与已有导入批次重复。');
      }
      batches.add(
        ImportBatchRecord(
          id: id,
          source: source,
          fingerprint: fingerprint,
          fileName: fileName,
          transactionCount: transactionCount,
          importedAt: importedAt.toUtc(),
        ),
      );
    }
    return batches;
  }

  List<Budget> _parseBudgets(Object? rawBudgets) {
    if (rawBudgets is! List<Object?>) {
      throw const BackupException('备份 budgets 必须是数组。');
    }

    final ids = <int>{};
    final identities = <String>{};
    final budgets = <Budget>[];
    for (var index = 0; index < rawBudgets.length; index += 1) {
      final map = _asMap(rawBudgets[index], 'budgets[$index]');
      _requireExactKeys(map, _requiredBudgetKeys, 'budgets[$index]');
      final budget = _parseBudget(map, index);
      if (!ids.add(budget.id)) {
        throw BackupException('备份包含重复预算 id: ${budget.id}。');
      }
      final identity = '${budget.categoryCode}|${budget.month}';
      if (!identities.add(identity)) {
        throw BackupException(
          '备份包含重复预算分类月份: ${budget.categoryCode} ${budget.month}。',
        );
      }
      budgets.add(budget);
    }
    return budgets;
  }

  Budget _parseBudget(Map<String, Object?> map, int index) {
    final prefix = 'budgets[$index]';
    final id = _readInt(map, 'id');
    if (id <= 0) {
      throw BackupException('$prefix.id 必须是正整数。');
    }

    final categoryCode = _readString(map, 'category_code');
    final month = _readString(map, 'month');
    final amountCents = _readInt(map, 'amount_cents');
    final enabledValue = _readInt(map, 'enabled');
    if (enabledValue != 0 && enabledValue != 1) {
      throw BackupException('$prefix.enabled 必须是 0 或 1。');
    }
    if (amountCents <= 0) {
      throw BackupException('$prefix.amount_cents 必须是正整数。');
    }

    final createdAt = _readTimestamp(map, 'created_at');
    final updatedAt = _readTimestamp(map, 'updated_at');
    if (updatedAt.isBefore(createdAt)) {
      throw BackupException('$prefix.updated_at 不能早于 created_at。');
    }

    try {
      BudgetValidator.validateCreate(
        NewBudget(
          categoryCode: categoryCode,
          month: month,
          amountCents: amountCents,
          enabled: enabledValue == 1,
        ),
      );
    } on BudgetValidationException catch (error) {
      throw BackupException('$prefix 数据无效: ${error.message}');
    }

    return Budget(
      id: id,
      categoryCode: categoryCode,
      month: month,
      amountCents: amountCents,
      enabled: enabledValue == 1,
      createdAt: createdAt.toUtc(),
      updatedAt: updatedAt.toUtc(),
    );
  }

  LedgerTransaction _parseTransaction(
    Map<String, Object?> map,
    int index, {
    required bool allowLegacyValues,
  }) {
    final prefix = 'transactions[$index]';
    final id = _readInt(map, 'id');
    if (id <= 0) {
      throw BackupException('$prefix.id 必须是正整数。');
    }

    final amountCents = _readAmountCents(map['amount_cents'], prefix);
    final typeCode = _readString(map, 'type');
    final type = TransactionType.tryFromCode(typeCode);
    if (type == null) {
      throw BackupException('$prefix.type 不是有效的收支类型。');
    }

    final rawCategory = _readString(map, 'category');
    final note = _readNullableString(map, 'note');
    final originalText = _readString(map, 'original_text');
    final transactionDate = _readString(map, 'transaction_date');
    final createdAt = _readTimestamp(map, 'created_at');
    final updatedAt = _readTimestamp(map, 'updated_at');
    final deletedAt = _readNullableTimestamp(map, 'deleted_at');

    if (updatedAt.isBefore(createdAt)) {
      throw BackupException('$prefix.updated_at 不能早于 created_at。');
    }

    final legacyCategory = allowLegacyValues
        ? _normalizeLegacyCategory(
            type: type,
            category: rawCategory,
            note: note,
            prefix: prefix,
          )
        : (category: rawCategory, note: note);
    if (allowLegacyValues) {
      _validateLegacyTransaction(
        prefix: prefix,
        amountCents: amountCents,
        type: type,
        category: legacyCategory.category,
        note: legacyCategory.note,
        originalText: originalText,
        transactionDate: transactionDate,
      );
    } else {
      try {
        TransactionValidator.validateCreate(
          NewLedgerTransaction(
            amountCents: amountCents,
            type: type,
            category: legacyCategory.category,
            note: legacyCategory.note,
            originalText: originalText,
            transactionDate: transactionDate,
          ),
          _clock,
        );
      } on TransactionValidationException catch (error) {
        throw BackupException('$prefix 数据无效: ${error.message}');
      }
    }

    return LedgerTransaction(
      id: id,
      amountCents: amountCents,
      type: type,
      category: legacyCategory.category,
      note: legacyCategory.note,
      originalText: originalText,
      transactionDate: transactionDate,
      createdAt: createdAt.toUtc(),
      updatedAt: updatedAt.toUtc(),
      deletedAt: deletedAt?.toUtc(),
    );
  }

  Object? _decodeJson(String rawJson) {
    try {
      return jsonDecode(rawJson);
    } on FormatException catch (error) {
      throw BackupException('备份文件不是有效 JSON: ${error.message}');
    }
  }

  Map<String, Object?> _asMap(Object? value, String label) {
    if (value is! Map) {
      throw BackupException('$label 必须是对象。');
    }
    try {
      return Map<String, Object?>.from(value);
    } on Object {
      throw BackupException('$label 包含无效字段名。');
    }
  }

  void _requireExactKeys(
    Map<String, Object?> map,
    Set<String> expected,
    String label,
  ) {
    if (map.keys.toSet().length != expected.length ||
        !map.keys.toSet().containsAll(expected)) {
      throw BackupException('$label 字段结构不完整或包含不支持的字段。');
    }
  }

  int _readInt(Map<String, Object?> map, String key) {
    final value = map[key];
    if (value is! int) {
      throw BackupException('$key 必须是整数。');
    }
    return value;
  }

  int _readAmountCents(Object? value, String prefix) {
    if (value is int) {
      return value;
    }
    if (value is double &&
        value.isFinite &&
        value == value.truncateToDouble() &&
        value <= DatabaseSchema.maxSqliteInteger &&
        value >= -DatabaseSchema.maxSqliteInteger) {
      return value.toInt();
    }
    throw BackupException('$prefix.amount_cents 必须是可安全转换的整数分。');
  }

  ({String category, String? note}) _normalizeLegacyCategory({
    required TransactionType type,
    required String category,
    required String? note,
    required String prefix,
  }) {
    final normalizedCategory = category.trim();
    if (CategoryCatalog.isValidForType(type, normalizedCategory)) {
      return (category: normalizedCategory, note: note);
    }

    final fallback = type == TransactionType.income
        ? 'other_income'
        : 'other_expense';
    final legacyNote = '原分类：$normalizedCategory';
    final normalizedNote = note?.trim();
    final combinedNote = normalizedNote == null || normalizedNote.isEmpty
        ? legacyNote
        : '$normalizedNote · $legacyNote';
    if (combinedNote.length > 200) {
      throw BackupException('$prefix 数据无效: 备注无法容纳原分类，拒绝静默丢失数据。');
    }
    return (category: fallback, note: combinedNote);
  }

  void _validateLegacyTransaction({
    required String prefix,
    required int amountCents,
    required TransactionType type,
    required String category,
    required String? note,
    required String originalText,
    required String transactionDate,
  }) {
    if (amountCents <= 0 || amountCents > maxTransactionAmountCents) {
      throw BackupException('$prefix.amount_cents 必须是大于 0 的整数分。');
    }
    if (!CategoryCatalog.isValidForType(type, category)) {
      throw BackupException('$prefix.category 与 type 不匹配。');
    }
    if (note != null && note.length > 200) {
      throw BackupException('$prefix.note 不能超过 200 个字符。');
    }
    if (originalText.trim().isEmpty) {
      throw BackupException('$prefix.original_text 不能为空。');
    }
    if (originalText.length > 500) {
      throw BackupException('$prefix.original_text 不能超过 500 个字符。');
    }
    if (transactionDate.length > 32) {
      throw BackupException('$prefix.transaction_date 长度异常。');
    }
  }

  String _readString(Map<String, Object?> map, String key) {
    final value = map[key];
    if (value is! String) {
      throw BackupException('$key 必须是字符串。');
    }
    return value;
  }

  String? _readNullableString(Map<String, Object?> map, String key) {
    final value = map[key];
    if (value != null && value is! String) {
      throw BackupException('$key 必须是字符串或 null。');
    }
    return value as String?;
  }

  DateTime _readTimestamp(Map<String, Object?> map, String key) {
    final value = _readString(map, key);
    final timestamp = DateTime.tryParse(value);
    if (timestamp == null) {
      throw BackupException('$key 不是有效时间戳。');
    }
    return timestamp;
  }

  DateTime? _readNullableTimestamp(Map<String, Object?> map, String key) {
    final value = map[key];
    if (value == null) {
      return null;
    }
    if (value is! String) {
      throw BackupException('$key 必须是时间戳或 null。');
    }
    final timestamp = DateTime.tryParse(value);
    if (timestamp == null) {
      throw BackupException('$key 不是有效时间戳。');
    }
    return timestamp;
  }

  String _formatFileStamp(DateTime value) {
    String twoDigits(int number) => number.toString().padLeft(2, '0');

    final local = value.toLocal();
    return '${local.year}${twoDigits(local.month)}${twoDigits(local.day)}-'
        '${twoDigits(local.hour)}${twoDigits(local.minute)}'
        '${twoDigits(local.second)}';
  }
}

final class _ParsedBackup {
  const _ParsedBackup({
    required this.transactions,
    required this.budgets,
    required this.importBatches,
  });

  final List<LedgerTransaction> transactions;
  final List<Budget> budgets;
  final List<ImportBatchRecord> importBatches;
}

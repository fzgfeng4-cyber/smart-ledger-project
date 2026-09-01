import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

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
    required this.createdAt,
  });

  final String filePath;
  final int transactionCount;
  final int deletedCount;
  final DateTime createdAt;

  String get fileName => path.basename(filePath);
}

final class BackupImportResult {
  const BackupImportResult({
    required this.filePath,
    required this.transactionCount,
    required this.deletedCount,
  });

  final String filePath;
  final int transactionCount;
  final int deletedCount;
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
    Clock? clock,
    this.backupDirectoryPath,
  }) : _clock = clock ?? const SystemClock();

  static const backupVersion = 1;
  static const appVersion = '1.0.0+1';

  final TransactionLocalDataSource dataSource;
  final Clock _clock;
  final String? backupDirectoryPath;

  Future<BackupExportResult> exportBackup() async {
    final entries = await dataSource.listAllForBackup();
    final createdAt = _clock.now().toUtc();
    final payload = <String, Object?>{
      'backup_version': backupVersion,
      'app_version': appVersion,
      'database_version': DatabaseSchema.version,
      'created_at': createdAt.toIso8601String(),
      'transactions': entries.map((entry) => entry.toMap()).toList(),
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
    final entries = _parseAndValidate(rawJson);
    try {
      await dataSource.replaceAllForBackup(entries);
    } on Object catch (error) {
      throw BackupException('恢复备份失败: $error');
    }

    return BackupImportResult(
      filePath: file.path,
      transactionCount: entries.length,
      deletedCount: entries.where((entry) => entry.isDeleted).length,
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

  List<LedgerTransaction> _parseAndValidate(String rawJson) {
    final decoded = _decodeJson(rawJson);
    final backup = _asMap(decoded, '备份根对象');
    _requireExactKeys(backup, _requiredBackupKeys, '备份根对象');

    final backupVersionValue = _readInt(backup, 'backup_version');
    if (backupVersionValue != backupVersion) {
      throw BackupException(
        '不支持的备份版本: $backupVersionValue，当前版本为 $backupVersion。',
      );
    }

    final databaseVersion = _readInt(backup, 'database_version');
    if (databaseVersion != DatabaseSchema.version) {
      throw BackupException(
        '不支持的数据库版本: $databaseVersion，当前版本为 ${DatabaseSchema.version}。',
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
      final entry = _parseTransaction(map, index);
      if (!ids.add(entry.id)) {
        throw BackupException('备份包含重复 id: ${entry.id}。');
      }
      entries.add(entry);
    }
    return entries;
  }

  LedgerTransaction _parseTransaction(Map<String, Object?> map, int index) {
    final prefix = 'transactions[$index]';
    final id = _readInt(map, 'id');
    if (id <= 0) {
      throw BackupException('$prefix.id 必须是正整数。');
    }

    final amountCents = _readInt(map, 'amount_cents');
    final typeCode = _readString(map, 'type');
    final type = TransactionType.tryFromCode(typeCode);
    if (type == null) {
      throw BackupException('$prefix.type 不是有效的收支类型。');
    }

    final category = _readString(map, 'category');
    final note = _readNullableString(map, 'note');
    final originalText = _readString(map, 'original_text');
    final transactionDate = _readString(map, 'transaction_date');
    final createdAt = _readTimestamp(map, 'created_at');
    final updatedAt = _readTimestamp(map, 'updated_at');
    final deletedAt = _readNullableTimestamp(map, 'deleted_at');

    if (updatedAt.isBefore(createdAt)) {
      throw BackupException('$prefix.updated_at 不能早于 created_at。');
    }

    try {
      TransactionValidator.validateCreate(
        NewLedgerTransaction(
          amountCents: amountCents,
          type: type,
          category: category,
          note: note,
          originalText: originalText,
          transactionDate: transactionDate,
        ),
        _clock,
      );
    } on TransactionValidationException catch (error) {
      throw BackupException('$prefix 数据无效: ${error.message}');
    }

    return LedgerTransaction(
      id: id,
      amountCents: amountCents,
      type: type,
      category: category,
      note: note,
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

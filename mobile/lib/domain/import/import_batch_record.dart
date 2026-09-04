final class ImportBatchRecord {
  const ImportBatchRecord({
    required this.id,
    required this.source,
    required this.fingerprint,
    required this.fileName,
    required this.transactionCount,
    required this.importedAt,
  });

  final int id;
  final String source;
  final String fingerprint;
  final String fileName;
  final int transactionCount;
  final DateTime importedAt;

  factory ImportBatchRecord.fromMap(Map<String, Object?> map) {
    final id = map['id'];
    final source = map['source'];
    final fingerprint = map['fingerprint'];
    final fileName = map['file_name'];
    final transactionCount = map['transaction_count'];
    final importedAt = map['imported_at'];
    if (id is! int ||
        source is! String ||
        fingerprint is! String ||
        fileName is! String ||
        transactionCount is! int ||
        importedAt is! String) {
      throw StateError('导入批次记录字段类型无效');
    }
    return ImportBatchRecord(
      id: id,
      source: source,
      fingerprint: fingerprint,
      fileName: fileName,
      transactionCount: transactionCount,
      importedAt: DateTime.parse(importedAt),
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'source': source,
      'fingerprint': fingerprint,
      'file_name': fileName,
      'transaction_count': transactionCount,
      'imported_at': importedAt.toUtc().toIso8601String(),
    };
  }
}

final class ImportBatchAlreadyExistsException implements Exception {
  const ImportBatchAlreadyExistsException();

  @override
  String toString() => '导入批次已存在';
}

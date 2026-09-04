import 'dart:convert';

abstract final class ImportLimits {
  const ImportLimits._();

  static const maxFileBytes = 10 * 1024 * 1024;
  static const maxCsvRecords = 100000;

  static void ensureBytesWithinLimit(int byteLength) {
    if (byteLength > maxFileBytes) {
      throw const ImportInputLimitException('CSV 文件超过 10 MB 大小上限，请拆分账单后重试。');
    }
  }

  static void ensureTextWithinLimit(String text) {
    ensureBytesWithinLimit(utf8.encode(text).length);
  }
}

final class ImportInputLimitException implements Exception {
  const ImportInputLimitException(this.message);

  final String message;

  @override
  String toString() => message;
}

enum ImportIssueSeverity {
  info('info'),
  warning('warning'),
  blocking('blocking');

  const ImportIssueSeverity(this.code);

  final String code;
}

abstract final class ImportIssueCodes {
  static const missingDate = 'missing_date';
  static const invalidDate = 'invalid_date';
  static const futureDate = 'future_date';
  static const missingAmount = 'missing_amount';
  static const invalidAmount = 'invalid_amount';
  static const noteTooLong = 'note_too_long';
  static const rawTextTooLong = 'raw_text_too_long';
  static const unknownDirection = 'unknown_direction';
  static const missingCategory = 'missing_category';
  static const invalidCategory = 'invalid_category';
  static const unknownMerchant = 'unknown_merchant';
  static const duplicateCandidate = 'duplicate_candidate';
  static const unknownRow = 'unknown_row';
  static const refundRow = 'refund_row';
  static const failedRow = 'failed_row';
  static const emptyRow = 'empty_row';
}

final class ImportIssue {
  const ImportIssue({
    required this.code,
    required this.severity,
    required this.message,
    this.field,
    List<String> candidates = const [],
  })
  // 保留私有列表并通过 getter 返回只读视图，避免 const 领域对象暴露可变集合。
  // ignore: prefer_initializing_formals
  : _candidates = candidates;

  final String code;
  final ImportIssueSeverity severity;
  final String? field;
  final String message;
  final List<String> _candidates;

  List<String> get candidates => List.unmodifiable(_candidates);

  bool get isBlocking => severity == ImportIssueSeverity.blocking;

  Map<String, Object?> toMap() {
    return {
      'code': code,
      'severity': severity.code,
      'field': field,
      'message': message,
      'candidates': candidates,
    };
  }
}

final class ImportDuplicateNotice {
  const ImportDuplicateNotice({
    required this.message,
    this.matchingTransactionId,
    this.matchKey,
  });

  final String message;
  final int? matchingTransactionId;
  final String? matchKey;

  Map<String, Object?> toMap() {
    return {
      'message': message,
      'matching_transaction_id': matchingTransactionId,
      'match_key': matchKey,
    };
  }
}

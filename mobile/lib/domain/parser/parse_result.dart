import '../models/transaction_type.dart';

enum ParseStatus {
  ready('ready'),
  needsConfirmation('needs_confirmation'),
  needsInput('needs_input'),
  noDraft('no_draft');

  const ParseStatus(this.code);

  final String code;
}

final class TransactionDraft {
  const TransactionDraft({
    required this.amountCents,
    required this.type,
    required this.category,
    required this.note,
    required this.originalText,
    required this.transactionDate,
  });

  final int? amountCents;
  final TransactionType? type;
  final String? category;
  final String? note;
  final String originalText;
  final String? transactionDate;

  Map<String, Object?> toMap() {
    return {
      'amount_cents': amountCents,
      'type': type?.code,
      'category': category,
      'note': note,
      'original_text': originalText,
      'transaction_date': transactionDate,
    };
  }
}

final class ParseIssue {
  ParseIssue({
    required this.code,
    required this.field,
    required this.message,
    List<String> candidates = const [],
  }) : candidates = List.unmodifiable(candidates);

  final String code;
  final String? field;
  final String message;
  final List<String> candidates;

  bool get isBlocking => _blockingCodes.contains(code);

  Map<String, Object?> toMap() {
    return {
      'code': code,
      'field': field,
      'message': message,
      'candidates': candidates,
    };
  }

  static const _blockingCodes = <String>{
    'MISSING_AMOUNT',
    'MULTIPLE_AMOUNTS',
    'INVALID_AMOUNT',
    'TYPE_UNKNOWN',
    'TYPE_CONFLICT',
    'MISSING_CATEGORY',
    'INVALID_NOTE',
    'INVALID_DATE',
    'UNSUPPORTED_DATE',
    'DATE_AMBIGUOUS',
    'FUTURE_DATE',
  };
}

final class ParseResult {
  ParseResult({
    required this.status,
    required this.originalText,
    required this.draft,
    List<String> missingFields = const [],
    List<ParseIssue> issues = const [],
  }) : missingFields = List.unmodifiable(missingFields),
       issues = List.unmodifiable(issues);

  final ParseStatus status;
  final String originalText;
  final TransactionDraft? draft;
  final List<String> missingFields;
  final List<ParseIssue> issues;

  bool get needsConfirmation {
    return status == ParseStatus.needsConfirmation ||
        status == ParseStatus.needsInput;
  }

  bool get requiresConfirmation => draft != null;

  bool get hasMultipleAmounts => hasIssue('MULTIPLE_AMOUNTS');

  bool get isMissingAmount => hasIssue('MISSING_AMOUNT');

  bool get hasFutureDate => hasIssue('FUTURE_DATE');

  bool get hasBlockingIssues => issues.any((issue) => issue.isBlocking);

  bool hasIssue(String code) {
    return issues.any((issue) => issue.code == code);
  }

  Map<String, Object?> toMap() {
    return {
      'status': status.code,
      'needs_confirmation': needsConfirmation,
      'requires_confirmation': requiresConfirmation,
      'draft': draft?.toMap(),
      'missing_fields': missingFields,
      'warnings': issues.map((issue) => issue.toMap()).toList(),
    };
  }
}

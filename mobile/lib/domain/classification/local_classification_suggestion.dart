import '../categories/category_catalog.dart';
import '../models/transaction_type.dart';

enum LocalClassificationSuggestionStatus {
  needsConfirmation('needs_confirmation'),
  needsInput('needs_input');

  const LocalClassificationSuggestionStatus(this.code);

  final String code;
}

final class ClassificationRuleHit {
  const ClassificationRuleHit({
    required this.ruleId,
    required this.field,
    required this.matchedText,
    required this.reason,
  });

  final String ruleId;
  final String field;
  final String matchedText;
  final String reason;

  Map<String, Object?> toMap() {
    return {
      'rule_id': ruleId,
      'field': field,
      'matched_text': matchedText,
      'reason': reason,
    };
  }
}

final class LocalClassificationSuggestion {
  LocalClassificationSuggestion({
    required this.originalText,
    required this.amountCents,
    required this.type,
    required this.categoryCode,
    required this.status,
    required this.isFallback,
    required List<ClassificationRuleHit> ruleHits,
    this.message,
  }) : ruleHits = List.unmodifiable(ruleHits);

  final String originalText;
  final int? amountCents;
  final TransactionType? type;
  final String? categoryCode;
  final LocalClassificationSuggestionStatus status;
  final bool isFallback;
  final List<ClassificationRuleHit> ruleHits;
  final String? message;

  String? get directionCode => type?.code;

  String? get categoryLabel {
    final code = categoryCode;
    return code == null ? null : CategoryCatalog.findByCode(code)?.label;
  }

  bool get needsConfirmation {
    return status == LocalClassificationSuggestionStatus.needsConfirmation;
  }

  bool get requiresConfirmation => needsConfirmation;

  Map<String, Object?> toMap() {
    return {
      'original_text': originalText,
      'amount_cents': amountCents,
      'type': type?.code,
      'direction': directionCode,
      'category_code': categoryCode,
      'category_label': categoryLabel,
      'status': status.code,
      'needs_confirmation': needsConfirmation,
      'requires_confirmation': requiresConfirmation,
      'is_fallback': isFallback,
      'message': message,
      'rule_hits': ruleHits.map((hit) => hit.toMap()).toList(),
    };
  }
}

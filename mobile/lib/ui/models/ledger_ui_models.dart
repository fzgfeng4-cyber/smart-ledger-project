import '../../domain/models/transaction_type.dart';

enum LedgerListStatus { idle, loading, error, end }

enum EditorMode { create, edit }

enum UiIssueSeverity { review, blocking }

final class UiIssue {
  const UiIssue({
    required this.code,
    required this.message,
    required this.severity,
    this.field,
    this.candidates = const [],
  });

  final String code;
  final String message;
  final UiIssueSeverity severity;
  final String? field;
  final List<String> candidates;
}

final class UiLedgerEntry {
  const UiLedgerEntry({
    required this.id,
    required this.amountCents,
    required this.type,
    required this.category,
    required this.note,
    required this.originalText,
    required this.transactionDate,
    this.deletedAt,
  });

  final int id;
  final int amountCents;
  final TransactionType type;
  final String category;
  final String? note;
  final String originalText;
  final String transactionDate;
  final DateTime? deletedAt;

  bool get isDeleted => deletedAt != null;

  UiLedgerEntry copyWith({
    int? amountCents,
    TransactionType? type,
    String? category,
    Object? note = _unset,
    String? originalText,
    String? transactionDate,
    DateTime? deletedAt,
    bool clearDeletedAt = false,
  }) {
    return UiLedgerEntry(
      id: id,
      amountCents: amountCents ?? this.amountCents,
      type: type ?? this.type,
      category: category ?? this.category,
      note: identical(note, _unset) ? this.note : note as String?,
      originalText: originalText ?? this.originalText,
      transactionDate: transactionDate ?? this.transactionDate,
      deletedAt: clearDeletedAt ? null : deletedAt ?? this.deletedAt,
    );
  }
}

final class EditorDraft {
  EditorDraft({
    required this.originalText,
    required this.amountText,
    required this.type,
    required this.category,
    required this.note,
    required this.transactionDate,
    required this.issues,
    required this.mode,
    this.sourceEntryId,
  }) : acknowledgedIssueCodes = <String>{},
       _initialAmountText = amountText,
       _initialType = type,
       _initialCategory = category,
       _initialNote = note,
       _initialTransactionDate = transactionDate;

  final String originalText;
  String amountText;
  TransactionType? type;
  String? category;
  String note;
  String transactionDate;
  final List<UiIssue> issues;
  final EditorMode mode;
  final int? sourceEntryId;
  final Set<String> acknowledgedIssueCodes;
  final String _initialAmountText;
  final TransactionType? _initialType;
  final String? _initialCategory;
  final String _initialNote;
  final String _initialTransactionDate;

  bool get hasBlockingIssue {
    return issues.any((issue) => issue.severity == UiIssueSeverity.blocking);
  }

  bool get hasUnresolvedReviewIssue {
    return issues.any(
      (issue) =>
          issue.severity == UiIssueSeverity.review &&
          !acknowledgedIssueCodes.contains(issue.code),
    );
  }

  List<UiIssue> get unresolvedIssues {
    return issues
        .where((issue) => !acknowledgedIssueCodes.contains(issue.code))
        .toList();
  }

  bool get isDirty {
    return amountText.trim() != _initialAmountText.trim() ||
        type != _initialType ||
        category != _initialCategory ||
        note.trim() != _initialNote.trim() ||
        transactionDate.trim() != _initialTransactionDate.trim();
  }
}

final class UndoDeleteState {
  const UndoDeleteState({required this.entry, required this.expiresAt});

  final UiLedgerEntry entry;
  final DateTime expiresAt;
}

final class _Unset {
  const _Unset();
}

const _unset = _Unset();

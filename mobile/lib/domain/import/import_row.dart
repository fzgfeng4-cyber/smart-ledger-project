import '../models/ledger_transaction.dart';
import '../models/transaction_type.dart';
import '../parser/batch_parse_result.dart';
import '../parser/parse_result.dart';
import 'import_issue.dart';

enum ImportRowStatus {
  candidate('candidate'),
  unknown('unknown'),
  refund('refund'),
  failed('failed'),
  empty('empty');

  const ImportRowStatus(this.code);

  final String code;
}

enum ImportReviewState {
  pending('pending'),
  confirmed('confirmed'),
  excluded('excluded');

  const ImportReviewState(this.code);

  final String code;
}

final class ImportRawRow {
  const ImportRawRow({
    required this.lineNumber,
    required this.rawText,
    List<String> fields = const [],
  })
  // 保留私有列表并通过 getter 返回只读视图，避免 const 领域对象暴露可变集合。
  // ignore: prefer_initializing_formals
  : _fields = fields;

  final int lineNumber;
  final String rawText;
  final List<String> _fields;

  List<String> get fields => List.unmodifiable(_fields);

  bool get isBlank {
    return rawText.trim().isEmpty &&
        _fields.every((field) => field.trim().isEmpty);
  }

  Map<String, Object?> toMap() {
    return {
      'line_number': lineNumber,
      'raw_text': rawText,
      'fields': fields,
    };
  }
}

final class ImportCategorySuggestion {
  const ImportCategorySuggestion({
    required this.categoryCode,
    this.reason,
  });

  final String categoryCode;
  final String? reason;

  Map<String, Object?> toMap() {
    return {
      'category_code': categoryCode,
      'reason': reason,
    };
  }
}

final class ImportDraftRow {
  ImportDraftRow({
    required ImportRawRow rawRow,
    ImportRowStatus status = ImportRowStatus.candidate,
    this.reviewState = ImportReviewState.pending,
    this.rawDate,
    this.transactionDate,
    this.rawAmount,
    this.amountCents,
    this.transactionType,
    this.merchant,
    this.note,
    Iterable<ImportCategorySuggestion> categorySuggestions = const [],
    Iterable<ImportIssue> issues = const [],
    this.duplicateNotice,
  }) : rawRow = rawRow,
       status = rawRow.isBlank ? ImportRowStatus.empty : status,
       categorySuggestions = List.unmodifiable(categorySuggestions),
       issues = List.unmodifiable(
         _withGeneratedIssues(
           rawRow: rawRow,
           status: rawRow.isBlank ? ImportRowStatus.empty : status,
           transactionDate: transactionDate,
           amountCents: amountCents,
           transactionType: transactionType,
           merchant: merchant,
           categorySuggestions: categorySuggestions,
           issues: issues,
           duplicateNotice: duplicateNotice,
         ),
       );

  final ImportRawRow rawRow;
  final ImportRowStatus status;
  final ImportReviewState reviewState;
  final String? rawDate;
  final String? transactionDate;
  final String? rawAmount;
  final int? amountCents;
  final TransactionType? transactionType;
  final String? merchant;
  final String? note;
  final List<ImportCategorySuggestion> categorySuggestions;
  final List<ImportIssue> issues;
  final ImportDuplicateNotice? duplicateNotice;

  String? get suggestedCategoryCode {
    if (categorySuggestions.isEmpty) {
      return null;
    }
    return categorySuggestions.first.categoryCode;
  }

  String? get ledgerNote {
    final parts = <String>[
      if (merchant != null && merchant!.trim().isNotEmpty) merchant!.trim(),
      if (note != null && note!.trim().isNotEmpty) note!.trim(),
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }

  bool get isCandidate => status == ImportRowStatus.candidate;

  bool get isEmpty => status == ImportRowStatus.empty;

  bool get isExcluded => reviewState == ImportReviewState.excluded;

  bool get hasBlockingIssues {
    return !isCandidate || issues.any((issue) => issue.isBlocking);
  }

  bool get requiresConfirmation {
    return isCandidate && !isExcluded;
  }

  bool get canConvertToTransaction {
    return isCandidate &&
        !isExcluded &&
        !hasBlockingIssues &&
        amountCents != null &&
        transactionType != null &&
        suggestedCategoryCode != null &&
        transactionDate != null;
  }

  bool get readyForSubmission {
    return canConvertToTransaction &&
        reviewState == ImportReviewState.confirmed;
  }

  NewLedgerTransaction? toNewLedgerTransaction() {
    if (!canConvertToTransaction) {
      return null;
    }

    final amount = amountCents;
    final type = transactionType;
    final category = suggestedCategoryCode;
    final date = transactionDate;
    if (amount == null || type == null || category == null || date == null) {
      return null;
    }

    return NewLedgerTransaction(
      amountCents: amount,
      type: type,
      category: category,
      note: ledgerNote,
      originalText: rawRow.rawText,
      transactionDate: date,
    );
  }

  ImportDraftRow confirm() {
    if (!canConvertToTransaction) {
      return this;
    }
    return copyWith(reviewState: ImportReviewState.confirmed);
  }

  ImportDraftRow exclude() {
    return copyWith(reviewState: ImportReviewState.excluded);
  }

  ImportDraftRow restore() {
    return copyWith(reviewState: ImportReviewState.pending);
  }

  ImportDraftRow unconfirm() {
    return copyWith(reviewState: ImportReviewState.pending);
  }

  BatchTransaction toBatchTransaction({int? candidateId}) {
    final blockingFields = <String>[];
    for (final issue in issues.where((issue) => issue.isBlocking)) {
      final field = issue.field;
      if (field != null && !blockingFields.contains(field)) {
        blockingFields.add(field);
      }
    }
    if (!isCandidate && !blockingFields.contains('row')) {
      blockingFields.add('row');
    }

    final draft = isCandidate
        ? TransactionDraft(
            amountCents: amountCents,
            type: transactionType,
            category: suggestedCategoryCode,
            note: ledgerNote,
            originalText: rawRow.rawText,
            transactionDate: transactionDate,
          )
        : null;
    final parseStatus = isEmpty
        ? ParseStatus.noDraft
        : hasBlockingIssues
        ? ParseStatus.needsInput
        : ParseStatus.needsConfirmation;

    return BatchTransaction(
      candidateId: candidateId ?? rawRow.lineNumber,
      originalLine: rawRow.rawText,
      parseResult: ParseResult(
        status: parseStatus,
        originalText: rawRow.rawText,
        draft: draft,
        missingFields: blockingFields,
        issues: issues
            .map(
              (issue) => ParseIssue(
                code: issue.code,
                field: issue.field,
                message: issue.message,
                candidates: issue.candidates,
              ),
            )
            .toList(),
      ),
      isExcluded: isExcluded,
      isConfirmed: reviewState == ImportReviewState.confirmed,
    );
  }

  ImportDraftRow copyWith({
    ImportRawRow? rawRow,
    ImportRowStatus? status,
    ImportReviewState? reviewState,
    Object? rawDate = _unset,
    Object? transactionDate = _unset,
    Object? rawAmount = _unset,
    Object? amountCents = _unset,
    Object? transactionType = _unset,
    Object? merchant = _unset,
    Object? note = _unset,
    Object? categorySuggestions = _unset,
    Object? issues = _unset,
    Object? duplicateNotice = _unset,
  }) {
    return ImportDraftRow(
      rawRow: rawRow ?? this.rawRow,
      status: status ?? this.status,
      reviewState: reviewState ?? this.reviewState,
      rawDate: identical(rawDate, _unset) ? this.rawDate : rawDate as String?,
      transactionDate: identical(transactionDate, _unset)
          ? this.transactionDate
          : transactionDate as String?,
      rawAmount: identical(rawAmount, _unset)
          ? this.rawAmount
          : rawAmount as String?,
      amountCents: identical(amountCents, _unset)
          ? this.amountCents
          : amountCents as int?,
      transactionType: identical(transactionType, _unset)
          ? this.transactionType
          : transactionType as TransactionType?,
      merchant: identical(merchant, _unset)
          ? this.merchant
          : merchant as String?,
      note: identical(note, _unset) ? this.note : note as String?,
      categorySuggestions: identical(categorySuggestions, _unset)
          ? this.categorySuggestions
          : categorySuggestions as Iterable<ImportCategorySuggestion>,
      issues: identical(issues, _unset)
          ? this.issues
          : issues as Iterable<ImportIssue>,
      duplicateNotice: identical(duplicateNotice, _unset)
          ? this.duplicateNotice
          : duplicateNotice as ImportDuplicateNotice?,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'raw_row': rawRow.toMap(),
      'status': status.code,
      'review_state': reviewState.code,
      'raw_date': rawDate,
      'transaction_date': transactionDate,
      'raw_amount': rawAmount,
      'amount_cents': amountCents,
      'type': transactionType?.code,
      'merchant': merchant,
      'note': note,
      'category_suggestions': categorySuggestions
          .map((suggestion) => suggestion.toMap())
          .toList(),
      'issues': issues.map((issue) => issue.toMap()).toList(),
      'duplicate_notice': duplicateNotice?.toMap(),
    };
  }
}

List<ImportIssue> _withGeneratedIssues({
  required ImportRawRow rawRow,
  required ImportRowStatus status,
  required String? transactionDate,
  required int? amountCents,
  required TransactionType? transactionType,
  required String? merchant,
  required Iterable<ImportCategorySuggestion> categorySuggestions,
  required Iterable<ImportIssue> issues,
  required ImportDuplicateNotice? duplicateNotice,
}) {
  final result = <ImportIssue>[...issues];

  void addIfMissing(ImportIssue issue, bool condition) {
    if (condition && !result.any((item) => item.code == issue.code)) {
      result.add(issue);
    }
  }

  addIfMissing(
    ImportIssue(
      code: _statusIssueCode(status),
      severity: ImportIssueSeverity.blocking,
      field: 'row',
      message: _statusIssueMessage(status),
    ),
    status != ImportRowStatus.candidate,
  );
  addIfMissing(
    const ImportIssue(
      code: ImportIssueCodes.missingAmount,
      severity: ImportIssueSeverity.blocking,
      field: 'amount_cents',
      message: '缺少金额。',
    ),
    status == ImportRowStatus.candidate &&
        amountCents == null &&
        !_hasFieldIssue(result, 'amount_cents'),
  );
  addIfMissing(
    const ImportIssue(
      code: ImportIssueCodes.unknownDirection,
      severity: ImportIssueSeverity.blocking,
      field: 'type',
      message: '无法判断收支方向。',
    ),
    status == ImportRowStatus.candidate &&
        transactionType == null &&
        !_hasFieldIssue(result, 'type'),
  );
  addIfMissing(
    const ImportIssue(
      code: ImportIssueCodes.missingCategory,
      severity: ImportIssueSeverity.blocking,
      field: 'category',
      message: '缺少分类建议。',
    ),
    status == ImportRowStatus.candidate &&
        !categorySuggestions.any((_) => true) &&
        !_hasFieldIssue(result, 'category'),
  );
  addIfMissing(
    const ImportIssue(
      code: ImportIssueCodes.missingDate,
      severity: ImportIssueSeverity.blocking,
      field: 'transaction_date',
      message: '缺少日期。',
    ),
    status == ImportRowStatus.candidate &&
        transactionDate == null &&
        !_hasFieldIssue(result, 'transaction_date'),
  );
  addIfMissing(
    const ImportIssue(
      code: ImportIssueCodes.unknownMerchant,
      severity: ImportIssueSeverity.warning,
      field: 'merchant',
      message: '未识别交易对方，请核对备注和分类。',
    ),
    status == ImportRowStatus.candidate &&
        (merchant == null || merchant.trim().isEmpty) &&
        !_hasFieldIssue(result, 'merchant'),
  );
  addIfMissing(
    ImportIssue(
      code: ImportIssueCodes.duplicateCandidate,
      severity: ImportIssueSeverity.warning,
      field: 'row',
      message: duplicateNotice?.message ?? '',
    ),
    duplicateNotice != null &&
        !result.any(
          (issue) => issue.code == ImportIssueCodes.duplicateCandidate,
        ),
  );

  return result;
}

bool _hasFieldIssue(Iterable<ImportIssue> issues, String field) {
  return issues.any((issue) => issue.field == field);
}

String _statusIssueCode(ImportRowStatus status) {
  return switch (status) {
    ImportRowStatus.candidate => '',
    ImportRowStatus.unknown => ImportIssueCodes.unknownRow,
    ImportRowStatus.refund => ImportIssueCodes.refundRow,
    ImportRowStatus.failed => ImportIssueCodes.failedRow,
    ImportRowStatus.empty => ImportIssueCodes.emptyRow,
  };
}

String _statusIssueMessage(ImportRowStatus status) {
  return switch (status) {
    ImportRowStatus.candidate => '',
    ImportRowStatus.unknown => '无法识别这行账单，已保留原始内容。',
    ImportRowStatus.refund => '这行是退款记录，暂不自动生成入账候选。',
    ImportRowStatus.failed => '这行交易失败，暂不生成入账候选。',
    ImportRowStatus.empty => '这是空行，未生成入账候选。',
  };
}

final class _Unset {
  const _Unset();
}

const _unset = _Unset();

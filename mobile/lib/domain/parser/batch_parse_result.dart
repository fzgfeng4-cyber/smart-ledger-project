import '../models/ledger_transaction.dart';
import 'parse_result.dart';

final class BatchTransaction {
  const BatchTransaction({
    required this.candidateId,
    required this.originalLine,
    required this.parseResult,
    this.isExcluded = false,
    this.isConfirmed = false,
  });

  final int candidateId;
  final String originalLine;
  final ParseResult parseResult;
  final bool isExcluded;
  final bool isConfirmed;

  TransactionDraft? get draft => parseResult.draft;

  bool get hasDraft => draft != null;

  bool get isEmpty => parseResult.status == ParseStatus.noDraft;

  bool get hasBlockingIssues {
    return !hasDraft ||
        parseResult.missingFields.isNotEmpty ||
        parseResult.hasBlockingIssues;
  }

  bool get requiresConfirmation {
    return hasDraft &&
        (parseResult.status != ParseStatus.ready ||
            parseResult.issues.isNotEmpty);
  }

  bool get canConvertToTransaction {
    final draft = this.draft;
    return !isExcluded &&
        draft != null &&
        !hasBlockingIssues &&
        draft.amountCents != null &&
        draft.type != null &&
        draft.category != null &&
        draft.transactionDate != null;
  }

  bool get readyForSubmission {
    return canConvertToTransaction && (!requiresConfirmation || isConfirmed);
  }

  NewLedgerTransaction? toNewLedgerTransaction() {
    if (!canConvertToTransaction) {
      return null;
    }

    final draft = this.draft!;
    return NewLedgerTransaction(
      amountCents: draft.amountCents!,
      type: draft.type!,
      category: draft.category!,
      note: draft.note,
      originalText: draft.originalText,
      transactionDate: draft.transactionDate!,
    );
  }

  BatchTransaction exclude() {
    return copyWith(isExcluded: true);
  }

  BatchTransaction restore() {
    return copyWith(isExcluded: false);
  }

  BatchTransaction confirm() {
    return copyWith(isConfirmed: true);
  }

  BatchTransaction unconfirm() {
    return copyWith(isConfirmed: false);
  }

  BatchTransaction copyWith({
    String? originalLine,
    ParseResult? parseResult,
    bool? isExcluded,
    bool? isConfirmed,
  }) {
    return BatchTransaction(
      candidateId: candidateId,
      originalLine: originalLine ?? this.originalLine,
      parseResult: parseResult ?? this.parseResult,
      isExcluded: isExcluded ?? this.isExcluded,
      isConfirmed: isConfirmed ?? this.isConfirmed,
    );
  }
}

final class BatchParseResult {
  BatchParseResult({
    required this.originalText,
    required Iterable<BatchTransaction> transactions,
  }) : transactions = List.unmodifiable(transactions);

  final String originalText;
  final List<BatchTransaction> transactions;

  List<BatchTransaction> get retainedTransactions {
    return List.unmodifiable(
      transactions.where((transaction) => !transaction.isExcluded),
    );
  }

  List<BatchTransaction> get excludedTransactions {
    return List.unmodifiable(
      transactions.where((transaction) => transaction.isExcluded),
    );
  }

  List<BatchTransaction> get nonEmptyTransactions {
    return List.unmodifiable(
      retainedTransactions.where((transaction) => !transaction.isEmpty),
    );
  }

  List<BatchTransaction> get blockingTransactions {
    return List.unmodifiable(
      retainedTransactions.where(
        (transaction) => transaction.hasBlockingIssues,
      ),
    );
  }

  List<BatchTransaction> get confirmationTransactions {
    return List.unmodifiable(
      retainedTransactions.where(
        (transaction) => transaction.requiresConfirmation,
      ),
    );
  }

  List<BatchTransaction> get unconfirmedTransactions {
    return List.unmodifiable(
      retainedTransactions.where(
        (transaction) =>
            transaction.requiresConfirmation && !transaction.isConfirmed,
      ),
    );
  }

  bool get hasBlockingIssues => blockingTransactions.isNotEmpty;

  bool get hasRetainedTransactions => retainedTransactions.isNotEmpty;

  bool get canSubmit {
    return hasRetainedTransactions &&
        !hasBlockingIssues &&
        nonEmptyTransactions.every(
          (transaction) => transaction.readyForSubmission,
        );
  }

  List<NewLedgerTransaction> get transactionsToSave {
    if (!canSubmit) {
      return const [];
    }
    return List.unmodifiable(
      nonEmptyTransactions
          .map((transaction) => transaction.toNewLedgerTransaction()!)
          .toList(),
    );
  }

  BatchTransaction? findById(int candidateId) {
    for (final transaction in transactions) {
      if (transaction.candidateId == candidateId) {
        return transaction;
      }
    }
    return null;
  }

  BatchParseResult exclude(int candidateId) {
    return _updateCandidate(
      candidateId,
      (transaction) => transaction.exclude(),
    );
  }

  BatchParseResult restore(int candidateId) {
    return _updateCandidate(
      candidateId,
      (transaction) => transaction.restore(),
    );
  }

  BatchParseResult updateCandidate(BatchTransaction candidate) {
    return _updateCandidate(candidate.candidateId, (_) => candidate);
  }

  BatchParseResult _updateCandidate(
    int candidateId,
    BatchTransaction Function(BatchTransaction transaction) update,
  ) {
    var found = false;
    final updated = transactions.map((transaction) {
      if (transaction.candidateId != candidateId) {
        return transaction;
      }
      found = true;
      return update(transaction);
    }).toList();
    if (!found) {
      return this;
    }
    return BatchParseResult(originalText: originalText, transactions: updated);
  }
}

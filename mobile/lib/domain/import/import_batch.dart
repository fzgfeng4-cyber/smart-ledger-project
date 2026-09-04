import '../models/ledger_transaction.dart';
import '../parser/batch_parse_result.dart';
import 'import_row.dart';
import 'import_source.dart';

final class ImportDraftBatch {
  ImportDraftBatch({
    required this.source,
    required Iterable<ImportDraftRow> rows,
    this.originalText = '',
  }) : rows = List.unmodifiable(rows);

  final ImportFileSource source;
  final String originalText;
  final List<ImportDraftRow> rows;

  List<ImportDraftRow> get retainedRows {
    return List.unmodifiable(rows.where((row) => !row.isExcluded));
  }

  List<ImportDraftRow> get excludedRows {
    return List.unmodifiable(rows.where((row) => row.isExcluded));
  }

  List<ImportDraftRow> get candidateRows {
    return List.unmodifiable(
      retainedRows.where((row) => row.status == ImportRowStatus.candidate),
    );
  }

  List<ImportDraftRow> get emptyRows {
    return List.unmodifiable(
      rows.where((row) => row.status == ImportRowStatus.empty),
    );
  }

  List<ImportDraftRow> get unknownRows {
    return List.unmodifiable(
      rows.where((row) => row.status == ImportRowStatus.unknown),
    );
  }

  List<ImportDraftRow> get refundRows {
    return List.unmodifiable(
      rows.where((row) => row.status == ImportRowStatus.refund),
    );
  }

  List<ImportDraftRow> get failedRows {
    return List.unmodifiable(
      rows.where((row) => row.status == ImportRowStatus.failed),
    );
  }

  List<ImportDraftRow> get blockingRows {
    return List.unmodifiable(
      retainedRows.where((row) => row.hasBlockingIssues),
    );
  }

  List<ImportDraftRow> get confirmationRows {
    return List.unmodifiable(
      candidateRows.where((row) => row.requiresConfirmation),
    );
  }

  bool get hasBlockingIssues => blockingRows.isNotEmpty;

  bool get canSubmit {
    return candidateRows.isNotEmpty &&
        !hasBlockingIssues &&
        candidateRows.every((row) => row.readyForSubmission);
  }

  List<NewLedgerTransaction> get transactionsToSave {
    if (!canSubmit) {
      return const [];
    }

    final transactions = <NewLedgerTransaction>[];
    for (final row in candidateRows) {
      final transaction = row.toNewLedgerTransaction();
      if (transaction == null) {
        return const [];
      }
      transactions.add(transaction);
    }
    return List.unmodifiable(transactions);
  }

  ImportDraftRow? findByLineNumber(int lineNumber) {
    for (final row in rows) {
      if (row.rawRow.lineNumber == lineNumber) {
        return row;
      }
    }
    return null;
  }

  ImportDraftBatch confirm(int lineNumber) {
    return _updateRow(lineNumber, (row) => row.confirm());
  }

  ImportDraftBatch unconfirm(int lineNumber) {
    return _updateRow(lineNumber, (row) => row.unconfirm());
  }

  ImportDraftBatch exclude(int lineNumber) {
    return _updateRow(lineNumber, (row) => row.exclude());
  }

  ImportDraftBatch restore(int lineNumber) {
    return _updateRow(lineNumber, (row) => row.restore());
  }

  ImportDraftBatch updateRow(ImportDraftRow row) {
    return _updateRow(row.rawRow.lineNumber, (_) => row);
  }

  BatchParseResult toBatchParseResult() {
    final batchText = originalText.isEmpty
        ? rows.map((row) => row.rawRow.rawText).join('\n')
        : originalText;
    return BatchParseResult(
      originalText: batchText,
      transactions: rows.map((row) => row.toBatchTransaction()),
    );
  }

  ImportDraftBatch _updateRow(
    int lineNumber,
    ImportDraftRow Function(ImportDraftRow row) update,
  ) {
    var found = false;
    final updated = rows.map((row) {
      if (row.rawRow.lineNumber != lineNumber) {
        return row;
      }
      found = true;
      return update(row);
    }).toList();
    if (!found) {
      return this;
    }
    return ImportDraftBatch(
      source: source,
      originalText: originalText,
      rows: updated,
    );
  }
}

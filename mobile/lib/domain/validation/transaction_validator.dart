import '../../shared/clock.dart';
import '../categories/category_catalog.dart';
import '../models/ledger_transaction.dart';
import '../models/transaction_type.dart';

final class TransactionValidationException implements Exception {
  const TransactionValidationException(this.message);

  final String message;

  @override
  String toString() => 'TransactionValidationException: $message';
}

final class TransactionValidator {
  const TransactionValidator._();

  static NewLedgerTransaction normalizeCreate(NewLedgerTransaction input) {
    return input.copyWith(
      category: input.category.trim(),
      note: normalizeNote(input.note),
      transactionDate: input.transactionDate.trim(),
    );
  }

  static LedgerTransactionUpdate normalizeUpdate(
    LedgerTransactionUpdate input,
  ) {
    if (input.hasNote) {
      return LedgerTransactionUpdate(
        amountCents: input.amountCents,
        type: input.type,
        category: input.category?.trim(),
        note: normalizeNote(input.note),
        transactionDate: input.transactionDate?.trim(),
      );
    }

    return LedgerTransactionUpdate(
      amountCents: input.amountCents,
      type: input.type,
      category: input.category?.trim(),
      transactionDate: input.transactionDate?.trim(),
    );
  }

  static void validateCreate(NewLedgerTransaction input, Clock clock) {
    _validateBusinessFields(
      amountCents: input.amountCents,
      type: input.type,
      category: input.category,
      note: input.note,
      originalText: input.originalText,
      transactionDate: input.transactionDate,
      clock: clock,
    );
  }

  static LedgerTransaction validateUpdateCandidate({
    required LedgerTransaction existing,
    required LedgerTransactionUpdate update,
    required Clock clock,
  }) {
    if (existing.isDeleted) {
      throw const TransactionValidationException('已删除账目不能直接编辑');
    }

    final candidate = update.hasNote
        ? existing.copyWith(
            amountCents: update.amountCents,
            type: update.type,
            category: update.category,
            note: update.note,
            transactionDate: update.transactionDate,
          )
        : existing.copyWith(
            amountCents: update.amountCents,
            type: update.type,
            category: update.category,
            transactionDate: update.transactionDate,
          );

    _validateBusinessFields(
      amountCents: candidate.amountCents,
      type: candidate.type,
      category: candidate.category,
      note: candidate.note,
      originalText: candidate.originalText,
      transactionDate: candidate.transactionDate,
      clock: clock,
    );

    return candidate;
  }

  static String? normalizeNote(String? note) {
    if (note == null) {
      return null;
    }
    final trimmed = note.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  static DateTime? parseTransactionDate(String value) {
    final match = _datePattern.firstMatch(value);
    if (match == null) {
      return null;
    }

    final year = int.parse(match.group(1)!);
    final month = int.parse(match.group(2)!);
    final day = int.parse(match.group(3)!);
    final parsed = DateTime(year, month, day);

    if (parsed.year != year || parsed.month != month || parsed.day != day) {
      return null;
    }
    return parsed;
  }

  static void _validateBusinessFields({
    required int amountCents,
    required TransactionType type,
    required String category,
    required String? note,
    required String originalText,
    required String transactionDate,
    required Clock clock,
  }) {
    if (amountCents <= 0) {
      throw const TransactionValidationException('金额必须是大于 0 的整数分');
    }

    if (!CategoryCatalog.isKnownCode(category)) {
      throw TransactionValidationException('未知分类 code: $category');
    }

    if (!CategoryCatalog.isValidForType(type, category)) {
      throw TransactionValidationException('分类 $category 不能用于 ${type.code}');
    }

    if (note != null && note.length > 200) {
      throw const TransactionValidationException('备注不能超过 200 个字符');
    }

    if (originalText.trim().isEmpty) {
      throw const TransactionValidationException('原始输入不能为空');
    }

    if (originalText.length > 500) {
      throw const TransactionValidationException('原始输入不能超过 500 个字符');
    }

    final parsedDate = parseTransactionDate(transactionDate);
    if (parsedDate == null) {
      throw TransactionValidationException(
        '账务日期必须是有效的 YYYY-MM-DD: $transactionDate',
      );
    }

    final now = clock.now();
    final today = DateTime(now.year, now.month, now.day);
    if (parsedDate.isAfter(today)) {
      throw TransactionValidationException('账务日期不能是未来日期: $transactionDate');
    }
  }

  static final _datePattern = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');
}

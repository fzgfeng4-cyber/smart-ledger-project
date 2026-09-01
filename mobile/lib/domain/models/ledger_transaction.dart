import 'transaction_type.dart';

final class LedgerTransaction {
  const LedgerTransaction({
    required this.id,
    required this.amountCents,
    required this.type,
    required this.category,
    required this.note,
    required this.originalText,
    required this.transactionDate,
    required this.createdAt,
    required this.updatedAt,
    required this.deletedAt,
  });

  final int id;
  final int amountCents;
  final TransactionType type;
  final String category;
  final String? note;
  final String originalText;
  final String transactionDate;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  bool get isDeleted => deletedAt != null;

  factory LedgerTransaction.fromMap(Map<String, Object?> map) {
    final deletedAtValue = map['deleted_at'];
    return LedgerTransaction(
      id: _readInt(map, 'id'),
      amountCents: _readInt(map, 'amount_cents'),
      type: TransactionType.fromCode(_readString(map, 'type')),
      category: _readString(map, 'category'),
      note: map['note'] as String?,
      originalText: _readString(map, 'original_text'),
      transactionDate: _readString(map, 'transaction_date'),
      createdAt: DateTime.parse(_readString(map, 'created_at')),
      updatedAt: DateTime.parse(_readString(map, 'updated_at')),
      deletedAt: deletedAtValue == null
          ? null
          : DateTime.parse(deletedAtValue as String),
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'amount_cents': amountCents,
      'type': type.code,
      'category': category,
      'note': note,
      'original_text': originalText,
      'transaction_date': transactionDate,
      'created_at': createdAt.toUtc().toIso8601String(),
      'updated_at': updatedAt.toUtc().toIso8601String(),
      'deleted_at': deletedAt?.toUtc().toIso8601String(),
    };
  }

  LedgerTransaction copyWith({
    int? id,
    int? amountCents,
    TransactionType? type,
    String? category,
    Object? note = _unset,
    String? originalText,
    String? transactionDate,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? deletedAt,
    bool clearDeletedAt = false,
  }) {
    assert(!clearDeletedAt || deletedAt == null);
    return LedgerTransaction(
      id: id ?? this.id,
      amountCents: amountCents ?? this.amountCents,
      type: type ?? this.type,
      category: category ?? this.category,
      note: identical(note, _unset) ? this.note : note as String?,
      originalText: originalText ?? this.originalText,
      transactionDate: transactionDate ?? this.transactionDate,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: clearDeletedAt ? null : deletedAt ?? this.deletedAt,
    );
  }
}

final class NewLedgerTransaction {
  const NewLedgerTransaction({
    required this.amountCents,
    required this.type,
    required this.category,
    required this.note,
    required this.originalText,
    required this.transactionDate,
  });

  final int amountCents;
  final TransactionType type;
  final String category;
  final String? note;
  final String originalText;
  final String transactionDate;

  NewLedgerTransaction copyWith({
    int? amountCents,
    TransactionType? type,
    String? category,
    Object? note = _unset,
    String? originalText,
    String? transactionDate,
  }) {
    return NewLedgerTransaction(
      amountCents: amountCents ?? this.amountCents,
      type: type ?? this.type,
      category: category ?? this.category,
      note: identical(note, _unset) ? this.note : note as String?,
      originalText: originalText ?? this.originalText,
      transactionDate: transactionDate ?? this.transactionDate,
    );
  }
}

final class LedgerTransactionUpdate {
  const LedgerTransactionUpdate({
    this.amountCents,
    this.type,
    this.category,
    Object? note = _unset,
    this.transactionDate,
  }) : _note = note == _unset ? _unset : note;

  final int? amountCents;
  final TransactionType? type;
  final String? category;
  final Object? _note;
  final String? transactionDate;

  bool get hasNote => !identical(_note, _unset);

  String? get note => _note as String?;

  bool get hasChanges {
    return amountCents != null ||
        type != null ||
        category != null ||
        hasNote ||
        transactionDate != null;
  }

  LedgerTransactionUpdate copyWith({
    int? amountCents,
    TransactionType? type,
    String? category,
    Object? note = _unset,
    String? transactionDate,
  }) {
    return LedgerTransactionUpdate(
      amountCents: amountCents ?? this.amountCents,
      type: type ?? this.type,
      category: category ?? this.category,
      note: identical(note, _unset) ? _note : note,
      transactionDate: transactionDate ?? this.transactionDate,
    );
  }
}

final class _Unset {
  const _Unset();
}

const _unset = _Unset();

int _readInt(Map<String, Object?> map, String key) {
  final value = map[key];
  if (value is int) {
    return value;
  }
  throw StateError('字段 $key 不是整数');
}

String _readString(Map<String, Object?> map, String key) {
  final value = map[key];
  if (value is String) {
    return value;
  }
  throw StateError('字段 $key 不是字符串');
}

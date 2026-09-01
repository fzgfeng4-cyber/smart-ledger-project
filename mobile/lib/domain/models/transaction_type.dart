enum TransactionType {
  expense('expense'),
  income('income');

  const TransactionType(this.code);

  final String code;

  static TransactionType fromCode(String code) {
    final value = tryFromCode(code);
    if (value == null) {
      throw ArgumentError.value(code, 'code', '未知收支类型');
    }
    return value;
  }

  static TransactionType? tryFromCode(String code) {
    final normalized = code.trim();
    for (final type in values) {
      if (type.code == normalized) {
        return type;
      }
    }
    return null;
  }
}

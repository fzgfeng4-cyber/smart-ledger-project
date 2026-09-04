final class Budget {
  const Budget({
    required this.id,
    required this.categoryCode,
    required this.month,
    required this.amountCents,
    required this.enabled,
    required this.createdAt,
    required this.updatedAt,
  });

  final int id;
  final String categoryCode;
  final String month;
  final int amountCents;
  final bool enabled;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory Budget.fromMap(Map<String, Object?> map) {
    final enabledValue = map['enabled'];
    if (enabledValue is! int || (enabledValue != 0 && enabledValue != 1)) {
      throw StateError('字段 enabled 不是 0 或 1');
    }

    return Budget(
      id: _readInt(map, 'id'),
      categoryCode: _readString(map, 'category_code'),
      month: _readString(map, 'month'),
      amountCents: _readInt(map, 'amount_cents'),
      enabled: enabledValue == 1,
      createdAt: DateTime.parse(_readString(map, 'created_at')),
      updatedAt: DateTime.parse(_readString(map, 'updated_at')),
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'category_code': categoryCode,
      'month': month,
      'amount_cents': amountCents,
      'enabled': enabled ? 1 : 0,
      'created_at': createdAt.toUtc().toIso8601String(),
      'updated_at': updatedAt.toUtc().toIso8601String(),
    };
  }

  Budget copyWith({
    int? id,
    String? categoryCode,
    String? month,
    int? amountCents,
    bool? enabled,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Budget(
      id: id ?? this.id,
      categoryCode: categoryCode ?? this.categoryCode,
      month: month ?? this.month,
      amountCents: amountCents ?? this.amountCents,
      enabled: enabled ?? this.enabled,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

final class NewBudget {
  const NewBudget({
    required this.categoryCode,
    required this.month,
    required this.amountCents,
    this.enabled = true,
  });

  final String categoryCode;
  final String month;
  final int amountCents;
  final bool enabled;

  NewBudget copyWith({
    String? categoryCode,
    String? month,
    int? amountCents,
    bool? enabled,
  }) {
    return NewBudget(
      categoryCode: categoryCode ?? this.categoryCode,
      month: month ?? this.month,
      amountCents: amountCents ?? this.amountCents,
      enabled: enabled ?? this.enabled,
    );
  }
}

final class BudgetUpdate {
  const BudgetUpdate({
    this.categoryCode,
    this.month,
    this.amountCents,
    this.enabled,
  });

  final String? categoryCode;
  final String? month;
  final int? amountCents;
  final bool? enabled;

  bool get hasChanges {
    return categoryCode != null ||
        month != null ||
        amountCents != null ||
        enabled != null;
  }
}

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

import '../../domain/categories/category_catalog.dart';
import '../../domain/models/transaction_type.dart';

String formatMoneyCents(int cents) {
  final absolute = cents.abs();
  final yuan = absolute ~/ 100;
  final fen = absolute % 100;
  final groupedYuan = _groupThousands(yuan.toString());
  return '¥$groupedYuan.${fen.toString().padLeft(2, '0')}';
}

String formatAmountInput(int cents) {
  final absolute = cents.abs();
  final yuan = absolute ~/ 100;
  final fen = absolute % 100;
  return '$yuan.${fen.toString().padLeft(2, '0')}';
}

int? parseYuanToCents(String rawValue) {
  final value = rawValue.trim();
  if (value.isEmpty || value.startsWith('-')) {
    return null;
  }

  final parts = value.split('.');
  if (parts.length > 2 || parts.first.isEmpty || !_isDigits(parts.first)) {
    return null;
  }

  final fraction = parts.length == 2 ? parts[1] : '';
  if (fraction.length > 2 || !_isDigits(fraction)) {
    return null;
  }

  final cents = int.tryParse('${parts.first}${fraction.padRight(2, '0')}');
  if (cents == null || cents <= 0) {
    return null;
  }
  return cents;
}

String transactionTypeLabel(TransactionType? type) {
  return switch (type) {
    TransactionType.expense => '支出',
    TransactionType.income => '收入',
    null => '待选择',
  };
}

String categoryLabel(String? code) {
  if (code == null) {
    return '待选择';
  }
  return CategoryCatalog.findByCode(code)?.label ?? '待选择';
}

String formatDateLabel(String? value, DateTime today) {
  if (value == null || value.trim().isEmpty) {
    return '待选择';
  }
  final parsed = DateTime.tryParse(value);
  if (parsed == null) {
    return value;
  }
  final date = DateTime(parsed.year, parsed.month, parsed.day);
  final todayOnly = DateTime(today.year, today.month, today.day);
  final relative = switch (todayOnly.difference(date).inDays) {
    0 => '今天',
    1 => '昨天',
    2 => '前天',
    _ => null,
  };
  final absolute = '${date.year}年${date.month}月${date.day}日';
  return relative == null ? absolute : '$relative · $absolute';
}

String formatIsoDate(DateTime value) {
  return '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';
}

bool isFutureDate(String? value, DateTime today) {
  if (value == null) {
    return false;
  }
  final parsed = DateTime.tryParse(value);
  if (parsed == null) {
    return false;
  }
  final date = DateTime(parsed.year, parsed.month, parsed.day);
  final todayOnly = DateTime(today.year, today.month, today.day);
  return date.isAfter(todayOnly);
}

String _groupThousands(String value) {
  final buffer = StringBuffer();
  for (var index = 0; index < value.length; index += 1) {
    final positionFromRight = value.length - index;
    buffer.write(value[index]);
    if (positionFromRight > 1 && positionFromRight % 3 == 1) {
      buffer.write(',');
    }
  }
  return buffer.toString();
}

bool _isDigits(String value) {
  if (value.isEmpty) {
    return true;
  }
  return RegExp(r'^\d+$').hasMatch(value);
}

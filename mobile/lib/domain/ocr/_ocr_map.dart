typedef OcrObjectMap = Map<String, Object?>;

OcrObjectMap readOcrMap(Object? value, String field) {
  if (value is OcrObjectMap) {
    return value;
  }
  if (value is Map) {
    final result = <String, Object?>{};
    for (final entry in value.entries) {
      if (entry.key is! String) {
        throw StateError('字段 $field 的对象键必须是字符串');
      }
      result[entry.key as String] = entry.value;
    }
    return result;
  }
  throw StateError('字段 $field 不是对象');
}

String readOcrString(OcrObjectMap map, String field) {
  final value = map[field];
  if (value is String) {
    return value;
  }
  throw StateError('字段 $field 不是字符串');
}

String? readOcrNullableString(OcrObjectMap map, String field) {
  final value = map[field];
  if (value == null || value is String) {
    return value as String?;
  }
  throw StateError('字段 $field 不是字符串或 null');
}

int? readOcrNullableInt(OcrObjectMap map, String field) {
  final value = map[field];
  if (value == null || value is int) {
    return value as int?;
  }
  throw StateError('字段 $field 不是整数或 null');
}

bool readOcrBool(OcrObjectMap map, String field) {
  final value = map[field];
  if (value is bool) {
    return value;
  }
  throw StateError('字段 $field 不是布尔值');
}

DateTime? readOcrNullableDateTime(OcrObjectMap map, String field) {
  final value = readOcrNullableString(map, field);
  return value == null ? null : DateTime.parse(value);
}

List<String> readOcrStringList(Object? value, String field) {
  if (value == null) {
    return const [];
  }
  if (value is! List) {
    throw StateError('字段 $field 不是列表');
  }
  final result = <String>[];
  for (final item in value) {
    if (item is! String) {
      throw StateError('字段 $field 的元素必须是字符串');
    }
    result.add(item);
  }
  return result;
}

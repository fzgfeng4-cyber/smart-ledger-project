import 'dart:convert';

import '../../domain/import/import_source.dart';

String importContentFingerprint({
  required ImportSourceType source,
  required String originalText,
}) {
  final normalizedText = originalText
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .replaceFirst('\uFEFF', '');
  final bytes = utf8.encode('${source.code}\u0000$normalizedText');
  final first = _fnv1a64(bytes, seed: 0xcbf29ce484222325);
  final second = _fnv1a64(bytes, seed: 0x4222325cbf29ce4d);
  return '${bytes.length}:${_hex64(first)}${_hex64(second)}';
}

int _fnv1a64(List<int> bytes, {required int seed}) {
  const mask = 0xffffffffffffffff;
  const prime = 0x100000001b3;
  var hash = seed;
  for (final byte in bytes) {
    hash = (hash ^ byte) * prime & mask;
  }
  return hash;
}

String _hex64(int value) {
  return value.toRadixString(16).padLeft(16, '0');
}

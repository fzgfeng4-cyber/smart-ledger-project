import '_ocr_map.dart';

enum OcrImageSourceType {
  camera('camera'),
  gallery('gallery'),
  file('file'),
  uri('uri'),
  unknown('unknown');

  const OcrImageSourceType(this.code);

  final String code;

  static OcrImageSourceType fromCode(String code) {
    final normalized = code.trim();
    for (final type in values) {
      if (type.code == normalized) {
        return type;
      }
    }
    throw ArgumentError.value(code, 'code', '未知 OCR 原图来源类型');
  }
}

enum OcrImageRetentionPolicy {
  discardAfterProcessing('discard_after_processing'),
  callerManaged('caller_managed');

  const OcrImageRetentionPolicy(this.code);

  final String code;

  static OcrImageRetentionPolicy fromCode(String code) {
    final normalized = code.trim();
    for (final policy in values) {
      if (policy.code == normalized) {
        return policy;
      }
    }
    throw ArgumentError.value(code, 'code', '未知 OCR 原图保留策略');
  }
}

final class OcrImageSource {
  const OcrImageSource({
    required this.type,
    this.ephemeralLocator,
    this.displayName,
    this.capturedAt,
  });

  final OcrImageSourceType type;

  /// 临时文件路径或 URI，仅供当前 OCR 请求使用，不是原图字节。
  final String? ephemeralLocator;

  final String? displayName;
  final DateTime? capturedAt;

  bool get hasEphemeralLocator {
    return ephemeralLocator?.trim().isNotEmpty == true;
  }

  /// 默认不序列化临时定位信息，调用方也不应把原图字节放进契约。
  Map<String, Object?> toMap({bool includeEphemeralLocator = false}) {
    return {
      'type': type.code,
      'display_name': displayName,
      'captured_at': capturedAt?.toUtc().toIso8601String(),
      if (includeEphemeralLocator && ephemeralLocator != null)
        'ephemeral_locator': ephemeralLocator,
    };
  }

  factory OcrImageSource.fromMap(Map<String, Object?> map) {
    return OcrImageSource(
      type: OcrImageSourceType.fromCode(
        readOcrString(map, 'type'),
      ),
      ephemeralLocator: readOcrNullableString(map, 'ephemeral_locator'),
      displayName: readOcrNullableString(map, 'display_name'),
      capturedAt: readOcrNullableDateTime(map, 'captured_at'),
    );
  }
}

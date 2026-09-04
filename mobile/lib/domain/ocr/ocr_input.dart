import '_ocr_map.dart';
import 'ocr_image_source.dart';

final class OcrInput {
  OcrInput({
    required this.requestId,
    required this.source,
    this.originalImagePolicy = OcrImageRetentionPolicy.discardAfterProcessing,
    this.requestedAt,
    Map<String, String> metadata = const {},
  }) : metadata = Map.unmodifiable(metadata);

  final String requestId;
  final OcrImageSource source;
  final OcrImageRetentionPolicy originalImagePolicy;
  final DateTime? requestedAt;
  final Map<String, String> metadata;

  /// OCR 输入只传递原图来源和临时定位信息，不接受图片字节。
  Map<String, Object?> toMap({bool includeEphemeralLocator = false}) {
    return {
      'request_id': requestId,
      'source': source.toMap(
        includeEphemeralLocator: includeEphemeralLocator,
      ),
      'original_image_policy': originalImagePolicy.code,
      'requested_at': requestedAt?.toUtc().toIso8601String(),
      'metadata': metadata,
    };
  }

  factory OcrInput.fromMap(Map<String, Object?> map) {
    final rawMetadata = map['metadata'];
    final parsedMetadata = <String, String>{};
    if (rawMetadata != null) {
      final metadata = readOcrMap(rawMetadata, 'metadata');
      for (final entry in metadata.entries) {
        if (entry.value is! String) {
          throw StateError('字段 metadata 的值必须是字符串');
        }
        parsedMetadata[entry.key] = entry.value as String;
      }
    }

    return OcrInput(
      requestId: readOcrString(map, 'request_id'),
      source: OcrImageSource.fromMap(readOcrMap(map['source'], 'source')),
      originalImagePolicy: OcrImageRetentionPolicy.fromCode(
        readOcrString(map, 'original_image_policy'),
      ),
      requestedAt: readOcrNullableDateTime(map, 'requested_at'),
      metadata: parsedMetadata,
    );
  }
}

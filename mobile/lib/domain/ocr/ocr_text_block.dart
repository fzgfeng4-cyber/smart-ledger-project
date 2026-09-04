import '_ocr_map.dart';
import 'ocr_confidence.dart';
import 'ocr_text_line.dart';

final class OcrTextBlock {
  OcrTextBlock({
    required this.blockIndex,
    required Iterable<OcrTextLine> lines,
    required this.confidence,
  }) : lines = List.unmodifiable(lines);

  final int blockIndex;
  final List<OcrTextLine> lines;
  final OcrConfidence confidence;

  String get text => lines.map((line) => line.text).join('\n');

  bool get isEmpty => text.trim().isEmpty;

  Map<String, Object?> toMap() {
    return {
      'block_index': blockIndex,
      'confidence': confidence.toMap(),
      'lines': lines.map((line) => line.toMap()).toList(),
    };
  }

  factory OcrTextBlock.fromMap(Map<String, Object?> map) {
    final rawLines = map['lines'];
    if (rawLines is! List) {
      throw StateError('字段 lines 不是列表');
    }
    return OcrTextBlock(
      blockIndex: readOcrNullableInt(map, 'block_index') ??
          (throw StateError('字段 block_index 不能为空')),
      confidence: OcrConfidence.fromMap(
        readOcrMap(map['confidence'], 'confidence'),
      ),
      lines: rawLines.map(
        (item) => OcrTextLine.fromMap(readOcrMap(item, 'lines')),
      ),
    );
  }
}

import '_ocr_map.dart';
import 'ocr_confidence.dart';

final class OcrTextLine {
  const OcrTextLine({
    required this.text,
    required this.confidence,
    this.lineIndex,
  });

  final String text;
  final OcrConfidence confidence;
  final int? lineIndex;

  bool get isEmpty => text.trim().isEmpty;

  Map<String, Object?> toMap() {
    return {
      'text': text,
      'confidence': confidence.toMap(),
      'line_index': lineIndex,
    };
  }

  factory OcrTextLine.fromMap(Map<String, Object?> map) {
    return OcrTextLine(
      text: readOcrString(map, 'text'),
      confidence: OcrConfidence.fromMap(
        readOcrMap(map['confidence'], 'confidence'),
      ),
      lineIndex: readOcrNullableInt(map, 'line_index'),
    );
  }
}

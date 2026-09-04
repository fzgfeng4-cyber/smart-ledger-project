import '_ocr_map.dart';

enum OcrIssueSeverity {
  info('info'),
  warning('warning'),
  blocking('blocking');

  const OcrIssueSeverity(this.code);

  final String code;

  static OcrIssueSeverity fromCode(String code) {
    final normalized = code.trim();
    for (final severity in values) {
      if (severity.code == normalized) {
        return severity;
      }
    }
    throw ArgumentError.value(code, 'code', '未知 OCR 问题级别');
  }
}

abstract final class OcrIssueCodes {
  static const emptyText = 'empty_text';
  static const lowConfidence = 'low_confidence';
  static const unreadable = 'unreadable';
  static const ambiguousText = 'ambiguous_text';
  static const numberUnitStuck = 'number_unit_stuck';
  static const unsupportedLayout = 'unsupported_layout';
}

final class OcrCandidateIssue {
  OcrCandidateIssue({
    required this.code,
    required this.severity,
    required this.message,
    this.fragment,
    this.blockIndex,
    this.lineIndex,
    Iterable<String> candidates = const [],
  }) : candidates = List.unmodifiable(candidates);

  final String code;
  final OcrIssueSeverity severity;
  final String message;
  final String? fragment;
  final int? blockIndex;
  final int? lineIndex;
  final List<String> candidates;

  bool get isBlocking => severity == OcrIssueSeverity.blocking;

  Map<String, Object?> toMap() {
    return {
      'code': code,
      'severity': severity.code,
      'message': message,
      'fragment': fragment,
      'block_index': blockIndex,
      'line_index': lineIndex,
      'candidates': candidates,
    };
  }

  factory OcrCandidateIssue.fromMap(Map<String, Object?> map) {
    return OcrCandidateIssue(
      code: readOcrString(map, 'code'),
      severity: OcrIssueSeverity.fromCode(
        readOcrString(map, 'severity'),
      ),
      message: readOcrString(map, 'message'),
      fragment: readOcrNullableString(map, 'fragment'),
      blockIndex: readOcrNullableInt(map, 'block_index'),
      lineIndex: readOcrNullableInt(map, 'line_index'),
      candidates: readOcrStringList(map['candidates'], 'candidates'),
    );
  }
}

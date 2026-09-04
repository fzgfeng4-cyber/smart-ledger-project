final class OcrConfidence {
  const OcrConfidence(this.value)
    : assert(value >= 0 && value <= 1);

  static const defaultLowThreshold = 0.7;

  final double value;

  bool isBelow({double threshold = defaultLowThreshold}) {
    if (!threshold.isFinite || threshold < 0 || threshold > 1) {
      throw ArgumentError.value(threshold, 'threshold', '置信度阈值必须在 0 到 1 之间');
    }
    return value < threshold;
  }

  Map<String, Object?> toMap() {
    return {'value': value};
  }

  factory OcrConfidence.fromMap(Map<String, Object?> map) {
    final rawValue = map['value'];
    if (rawValue is! num) {
      throw StateError('字段 value 不是数字');
    }
    return OcrConfidence(rawValue.toDouble());
  }
}

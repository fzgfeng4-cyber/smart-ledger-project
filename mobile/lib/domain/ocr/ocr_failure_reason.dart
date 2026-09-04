import '_ocr_map.dart';

abstract final class OcrFailureCodes {
  static const recognitionFailed = 'recognition_failed';
  static const permissionDenied = 'permission_denied';
  static const cancelled = 'cancelled';
  static const invalidInput = 'invalid_input';
  static const providerUnavailable = 'provider_unavailable';
}

final class OcrFailureReason {
  const OcrFailureReason({
    required this.code,
    required this.message,
    this.retryable = false,
  });

  final String code;
  final String message;
  final bool retryable;

  Map<String, Object?> toMap() {
    return {
      'code': code,
      'message': message,
      'retryable': retryable,
    };
  }

  factory OcrFailureReason.fromMap(Map<String, Object?> map) {
    return OcrFailureReason(
      code: readOcrString(map, 'code'),
      message: readOcrString(map, 'message'),
      retryable: readOcrBool(map, 'retryable'),
    );
  }
}

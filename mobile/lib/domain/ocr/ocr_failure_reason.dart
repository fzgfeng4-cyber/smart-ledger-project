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

  /// 只向用户展示可理解的错误文本，避免把平台异常原文泄漏到界面。
  String get displayMessage => sanitizeOcrFailureMessage(message, code: code);

  Map<String, Object?> toMap() {
    return {'code': code, 'message': message, 'retryable': retryable};
  }

  factory OcrFailureReason.fromMap(Map<String, Object?> map) {
    final code = readOcrString(map, 'code');
    final message = readOcrString(map, 'message');
    return OcrFailureReason(
      code: code,
      message: sanitizeOcrFailureMessage(message, code: code),
      retryable: readOcrBool(map, 'retryable'),
    );
  }
}

String sanitizeOcrFailureMessage(String message, {String? code}) {
  final normalized = message.trim();
  if (normalized.isEmpty) {
    return _defaultOcrFailureMessage(code);
  }

  final lower = normalized.toLowerCase();
  final containsPlatformDetails =
      lower.contains('attempt to invoke virtual method') ||
      lower.contains('nullpointerexception') ||
      lower.contains('java.lang.') ||
      lower.contains('android.') && lower.contains('exception');
  if (!containsPlatformDetails) {
    return normalized;
  }

  return _defaultOcrFailureMessage(code);
}

String _defaultOcrFailureMessage(String? code) {
  switch (code) {
    case OcrFailureCodes.invalidInput:
      return '图片不存在或无法读取，请重新选择清晰图片。';
    case OcrFailureCodes.permissionDenied:
      return '未获得图片访问权限，请允许权限后重试。';
    case OcrFailureCodes.cancelled:
      return '用户取消了图片选择或 OCR 识别。';
    case OcrFailureCodes.providerUnavailable:
      return '本地 OCR 暂时不可用，请稍后重试。';
    default:
      return '本地 OCR 识别失败，请更换清晰图片后重试。';
  }
}

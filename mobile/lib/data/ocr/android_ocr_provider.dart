import 'package:flutter/services.dart';

import '../../domain/ocr/ocr_contract.dart';

/// Android 本地 OCR provider。
///
/// 图片只通过临时 URI/路径交给 Android 平台通道，识别结果仍然只是建议，
/// 不会触碰数据库或网络。
final class AndroidOcrProvider implements OcrProvider {
  AndroidOcrProvider({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(channelName);

  static const channelName = 'smartledger/ocr';
  static const recognizeMethod = 'recognize';
  static const pickAndRecognizeMethod = 'pickAndRecognize';
  static const cancelMethod = 'cancel';
  static const openAppSettingsMethod = 'openAppSettings';

  final MethodChannel _channel;

  @override
  Future<OcrResult> recognize(OcrInput input) {
    final safeInput = _safeInput(input);
    if (!input.source.hasEphemeralLocator) {
      return Future.value(
        _failed(
          safeInput,
          code: OcrFailureCodes.invalidInput,
          message: '没有可读取的图片定位信息。',
        ),
      );
    }
    return _invoke(
      method: recognizeMethod,
      input: safeInput,
      arguments: safeInput.toMap(includeEphemeralLocator: true),
    );
  }

  /// 主动打开相机或相册并在本地完成一次识别。
  Future<OcrResult> pickAndRecognize({
    required String requestId,
    required OcrImageSourceType source,
    OcrImageRetentionPolicy originalImagePolicy =
        OcrImageRetentionPolicy.discardAfterProcessing,
    DateTime? requestedAt,
    Map<String, String> metadata = const {},
  }) {
    final input = _safeInput(
      OcrInput(
        requestId: requestId,
        source: OcrImageSource(type: source),
        originalImagePolicy: originalImagePolicy,
        requestedAt: requestedAt,
        metadata: metadata,
      ),
    );
    if (source != OcrImageSourceType.camera &&
        source != OcrImageSourceType.gallery) {
      return Future.value(
        _failed(
          input,
          code: OcrFailureCodes.invalidInput,
          message: '图片选择来源必须是相机或相册。',
        ),
      );
    }
    return _invoke(
      method: pickAndRecognizeMethod,
      input: input,
      arguments: {
        'request_id': input.requestId,
        'source_type': source.code,
        'original_image_policy': input.originalImagePolicy.code,
        'requested_at': input.requestedAt?.toUtc().toIso8601String(),
        'metadata': input.metadata,
      },
    );
  }

  Future<OcrResult> recognizeFromCamera({
    required String requestId,
    OcrImageRetentionPolicy originalImagePolicy =
        OcrImageRetentionPolicy.discardAfterProcessing,
    DateTime? requestedAt,
    Map<String, String> metadata = const {},
  }) {
    return pickAndRecognize(
      requestId: requestId,
      source: OcrImageSourceType.camera,
      originalImagePolicy: originalImagePolicy,
      requestedAt: requestedAt,
      metadata: metadata,
    );
  }

  Future<OcrResult> recognizeFromGallery({
    required String requestId,
    OcrImageRetentionPolicy originalImagePolicy =
        OcrImageRetentionPolicy.discardAfterProcessing,
    DateTime? requestedAt,
    Map<String, String> metadata = const {},
  }) {
    return pickAndRecognize(
      requestId: requestId,
      source: OcrImageSourceType.gallery,
      originalImagePolicy: originalImagePolicy,
      requestedAt: requestedAt,
      metadata: metadata,
    );
  }

  /// 取消当前相机/相册或识别请求；原请求会收到 cancelled 结果。
  Future<bool> cancel() async {
    try {
      return await _channel.invokeMethod<bool>(cancelMethod) ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  Future<bool> openAppSettings() async {
    try {
      return await _channel.invokeMethod<bool>(openAppSettingsMethod) ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  Future<OcrResult> _invoke({
    required String method,
    required OcrInput input,
    required Object? arguments,
  }) async {
    try {
      final raw = await _channel.invokeMethod<Object?>(method, arguments);
      if (raw == null) {
        return _failed(
          input,
          code: OcrFailureCodes.providerUnavailable,
          message: 'Android 本地 OCR 通道没有返回结果。',
        );
      }
      return OcrResult.fromMap(_asMap(raw));
    } on MissingPluginException {
      return _failed(
        input,
        code: OcrFailureCodes.providerUnavailable,
        message: 'Android 本地 OCR 通道不可用。',
      );
    } on PlatformException catch (error) {
      return _platformFailure(input, error);
    } on Object {
      return _failed(
        input,
        code: OcrFailureCodes.recognitionFailed,
        message: 'Android OCR 结果无法解析，请重试。',
        retryable: true,
      );
    }
  }

  OcrResult _platformFailure(OcrInput input, PlatformException error) {
    final code = error.code.toLowerCase();
    if (code.contains('permission')) {
      return OcrResult.permissionDenied(
        input: input,
        failureReason: OcrFailureReason(
          code: OcrFailureCodes.permissionDenied,
          message: '未获得相机权限。',
        ),
      );
    }
    if (code.contains('cancel')) {
      return OcrResult.cancelled(
        input: input,
        failureReason: OcrFailureReason(
          code: OcrFailureCodes.cancelled,
          message: '用户取消了图片选择或 OCR 识别。',
        ),
      );
    }
    if (code.contains('input') || code.contains('image')) {
      return _failed(
        input,
        code: OcrFailureCodes.invalidInput,
        message: '图片不存在或无法读取。',
      );
    }
    return _failed(
      input,
      code: OcrFailureCodes.providerUnavailable,
      message: 'Android 本地 OCR 调用失败，请重试。',
      retryable: true,
    );
  }

  static Map<String, Object?> _asMap(Object raw) {
    if (raw is! Map) {
      throw const FormatException('Android OCR 返回值不是对象。');
    }
    final result = <String, Object?>{};
    for (final entry in raw.entries) {
      if (entry.key is! String) {
        throw const FormatException('Android OCR 返回对象的键不是字符串。');
      }
      result[entry.key as String] = entry.value;
    }
    return result;
  }

  static OcrInput _safeInput(OcrInput input) {
    if (input.requestId.trim().isNotEmpty) {
      return input;
    }
    return OcrInput(
      requestId: 'ocr-invalid-request',
      source: input.source,
      originalImagePolicy: input.originalImagePolicy,
      requestedAt: input.requestedAt,
      metadata: input.metadata,
    );
  }

  static OcrResult _failed(
    OcrInput input, {
    required String code,
    required String message,
    bool retryable = false,
  }) {
    return OcrResult.failed(
      input: input,
      failureReason: OcrFailureReason(
        code: code,
        message: message,
        retryable: retryable,
      ),
    );
  }
}

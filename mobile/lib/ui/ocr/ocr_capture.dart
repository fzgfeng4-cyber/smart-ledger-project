import '../../data/ocr/android_ocr_provider.dart';
import '../../domain/ocr/ocr_contract.dart';

abstract interface class OcrCaptureService {
  Future<OcrResult> pickAndRecognize({
    required OcrImageSourceType source,
    required String requestId,
  });

  Future<bool> cancel();

  Future<bool> openAppSettings();
}

final class AndroidOcrCaptureService implements OcrCaptureService {
  AndroidOcrCaptureService({AndroidOcrProvider? provider})
    : _provider = provider ?? AndroidOcrProvider();

  final AndroidOcrProvider _provider;

  @override
  Future<bool> cancel() => _provider.cancel();

  @override
  Future<bool> openAppSettings() => _provider.openAppSettings();

  @override
  Future<OcrResult> pickAndRecognize({
    required OcrImageSourceType source,
    required String requestId,
  }) {
    return _provider.pickAndRecognize(requestId: requestId, source: source);
  }
}

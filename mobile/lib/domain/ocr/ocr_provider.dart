import 'ocr_input.dart';
import 'ocr_result.dart';

/// OCR provider 只负责把一次输入转换为 OCR 结果。
///
/// 实现可以调用设备上的离线识别能力，但不能通过该契约写数据库、上传网络
/// 或直接生成可入账交易。识别结果仍需经过解析、用户确认和现有入库流程。
abstract interface class OcrProvider {
  Future<OcrResult> recognize(OcrInput input);
}

import 'package:flutter_test/flutter_test.dart';
import 'package:smartledger/domain/ocr/ocr_contract.dart';

void main() {
  test('provider 接口只返回 OCR 结果，并把请求原样交给离线实现', () async {
    final input = OcrInput(
      requestId: 'provider-test-1',
      source: const OcrImageSource(
        type: OcrImageSourceType.file,
        ephemeralLocator: '/cache/ticket.png',
      ),
    );
    final expected = OcrResult.success(
      input: input,
      recognizedText: '公交 2 元',
    );
    final provider = _FakeOcrProvider(expected);

    final actual = await provider.recognize(input);

    expect(identical(actual, expected), isTrue);
    expect(provider.calls, 1);
    expect(identical(provider.lastInput, input), isTrue);
  });
}

final class _FakeOcrProvider implements OcrProvider {
  _FakeOcrProvider(this.result);

  final OcrResult result;
  int calls = 0;
  OcrInput? lastInput;

  @override
  Future<OcrResult> recognize(OcrInput input) async {
    calls += 1;
    lastInput = input;
    return result;
  }
}

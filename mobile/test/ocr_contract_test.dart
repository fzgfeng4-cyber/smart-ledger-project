import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:smartledger/domain/ocr/ocr_contract.dart';

void main() {
  test('OCR 输入默认只持久化来源元数据，不保存原图字节或临时定位信息', () {
    final input = _input();

    expect(
      input.originalImagePolicy,
      OcrImageRetentionPolicy.discardAfterProcessing,
    );
    final persisted = input.toMap();
    final source = persisted['source']! as Map<String, Object?>;
    expect(source['type'], 'gallery');
    expect(source.containsKey('ephemeral_locator'), isFalse);
    expect(jsonEncode(persisted), isNot(contains('image_bytes')));
    expect(jsonEncode(persisted), isNot(contains('原图字节')));

    final runtimeOnly = input.toMap(includeEphemeralLocator: true);
    final runtimeSource = runtimeOnly['source']! as Map<String, Object?>;
    expect(runtimeSource['ephemeral_locator'], '/cache/receipt.jpg');
  });

  test('待处理、空文本和成功状态可序列化并保留原始识别文本', () {
    final input = _input();
    final pending = OcrResult.pending(input: input);
    final empty = OcrResult.emptyText(input: input);
    final success = OcrResult.success(
      input: input,
      recognizedText: '超市\n合计 35.00 元',
      completedAt: DateTime.utc(2026, 9, 1, 10),
    );

    expect(pending.status, OcrStatus.pending);
    expect(pending.isTerminal, isFalse);
    expect(empty.status, OcrStatus.emptyText);
    expect(empty.hasText, isFalse);
    expect(success.status, OcrStatus.success);
    expect(success.recognizedText, '超市\n合计 35.00 元');
    expect(OcrResult.fromMap(success.toMap()).recognizedText, success.recognizedText);
    expect(jsonEncode(success.toMap()), contains('recognized_text'));
  });

  test('多行小票保留文本块、行级置信度和行序号', () {
    final input = _input();
    final block = OcrTextBlock(
      blockIndex: 0,
      confidence: const OcrConfidence(0.96),
      lines: const [
        OcrTextLine(
          lineIndex: 0,
          text: '邻里超市',
          confidence: OcrConfidence(0.99),
        ),
        OcrTextLine(
          lineIndex: 1,
          text: '合计 35.00 元',
          confidence: OcrConfidence(0.93),
        ),
      ],
    );
    final result = OcrResult.success(
      input: input,
      recognizedText: '邻里超市\n合计 35.00 元',
      blocks: [block],
      confidence: const OcrConfidence(0.96),
    );

    expect(result.blocks, hasLength(1));
    expect(result.blocks.single.text, '邻里超市\n合计 35.00 元');
    expect(result.blocks.single.lines[1].lineIndex, 1);
    expect(result.blocks.single.lines[1].confidence.value, 0.93);
    final roundTrip = OcrResult.fromMap(result.toMap());
    expect(roundTrip.blocks.single.lines, hasLength(2));
    expect(roundTrip.blocks.single.text, result.blocks.single.text);
  });

  test('低置信度结果保留候选问题并要求人工复核', () {
    final result = OcrResult.lowConfidence(
      input: _input(),
      recognizedText: '合计 35.00 元',
      confidence: const OcrConfidence(0.42),
      candidateIssues: [
        OcrCandidateIssue(
          code: OcrIssueCodes.lowConfidence,
          severity: OcrIssueSeverity.warning,
          message: '金额行置信度较低，请核对原始图片。',
          fragment: '35.00',
          lineIndex: 0,
          candidates: const ['35.00', '85.00'],
        ),
      ],
    );

    expect(result.status, OcrStatus.lowConfidence);
    expect(result.confidence!.isBelow(), isTrue);
    expect(result.requiresReview, isTrue);
    expect(result.candidateIssues.single.candidates, ['35.00', '85.00']);
    expect(
      OcrResult.fromMap(result.toMap()).candidateIssues.single.code,
      OcrIssueCodes.lowConfidence,
    );
  });

  test('数字和单位粘连时保留识别原文，并把问题交给后续候选审阅', () {
    const stuckText = '实付35.00元';
    final line = OcrTextLine(
      text: stuckText,
      confidence: const OcrConfidence(0.88),
      lineIndex: 0,
    );
    final result = OcrResult.success(
      input: _input(),
      recognizedText: stuckText,
      blocks: [
        OcrTextBlock(
          blockIndex: 0,
          confidence: const OcrConfidence(0.88),
          lines: [line],
        ),
      ],
      candidateIssues: [
        OcrCandidateIssue(
          code: OcrIssueCodes.numberUnitStuck,
          severity: OcrIssueSeverity.warning,
          message: '数字和金额单位粘连，后续解析需要保留原文并复核。',
          fragment: '35.00元',
          lineIndex: 0,
        ),
      ],
    );

    expect(result.recognizedText, stuckText);
    expect(result.blocks.single.lines.single.text, stuckText);
    expect(result.candidateIssues.single.code, OcrIssueCodes.numberUnitStuck);
    expect(result.toMap()['recognized_text'], stuckText);
  });

  test('识别失败、取消和无权限都能观察到明确失败原因', () {
    final failed = OcrResult.failed(
      input: _input(),
      failureReason: const OcrFailureReason(
        code: OcrFailureCodes.recognitionFailed,
        message: '离线识别引擎处理失败。',
        retryable: true,
      ),
    );
    final cancelled = OcrResult.cancelled(input: _input());
    final permissionDenied = OcrResult.permissionDenied(input: _input());

    expect(failed.status, OcrStatus.failed);
    expect(failed.isFailure, isTrue);
    expect(failed.failureReason!.retryable, isTrue);
    expect(cancelled.status, OcrStatus.cancelled);
    expect(cancelled.failureReason!.code, OcrFailureCodes.cancelled);
    expect(permissionDenied.status, OcrStatus.permissionDenied);
    expect(
      permissionDenied.failureReason!.code,
      OcrFailureCodes.permissionDenied,
    );
    expect(
      OcrResult.fromMap(permissionDenied.toMap()).failureReason!.message,
      permissionDenied.failureReason!.message,
    );
  });
}

OcrInput _input() {
  return OcrInput(
    requestId: 'ocr-test-1',
    source: const OcrImageSource(
      type: OcrImageSourceType.gallery,
      ephemeralLocator: '/cache/receipt.jpg',
      displayName: 'receipt.jpg',
    ),
    requestedAt: DateTime.utc(2026, 9, 1, 9),
  );
}

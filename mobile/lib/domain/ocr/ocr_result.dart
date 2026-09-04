import '_ocr_map.dart';
import 'ocr_candidate_issue.dart';
import 'ocr_confidence.dart';
import 'ocr_failure_reason.dart';
import 'ocr_image_source.dart';
import 'ocr_input.dart';
import 'ocr_status.dart';
import 'ocr_text_block.dart';

final class OcrResult {
  OcrResult({
    required this.requestId,
    required this.source,
    required this.status,
    required this.recognizedText,
    Iterable<OcrTextBlock> blocks = const [],
    this.confidence,
    Iterable<OcrCandidateIssue> candidateIssues = const [],
    this.failureReason,
    this.completedAt,
  }) : blocks = List.unmodifiable(blocks),
       candidateIssues = List.unmodifiable(candidateIssues) {
    _validate();
  }

  final String requestId;
  final OcrImageSource source;
  final OcrStatus status;
  final String recognizedText;
  final List<OcrTextBlock> blocks;
  final OcrConfidence? confidence;
  final List<OcrCandidateIssue> candidateIssues;
  final OcrFailureReason? failureReason;
  final DateTime? completedAt;

  factory OcrResult.pending({required OcrInput input}) {
    return OcrResult(
      requestId: input.requestId,
      source: input.source,
      status: OcrStatus.pending,
      recognizedText: '',
    );
  }

  factory OcrResult.success({
    required OcrInput input,
    required String recognizedText,
    Iterable<OcrTextBlock> blocks = const [],
    OcrConfidence? confidence,
    Iterable<OcrCandidateIssue> candidateIssues = const [],
    DateTime? completedAt,
  }) {
    return OcrResult(
      requestId: input.requestId,
      source: input.source,
      status: OcrStatus.success,
      recognizedText: recognizedText,
      blocks: blocks,
      confidence: confidence,
      candidateIssues: candidateIssues,
      completedAt: completedAt,
    );
  }

  factory OcrResult.emptyText({
    required OcrInput input,
    Iterable<OcrCandidateIssue> candidateIssues = const [],
    DateTime? completedAt,
  }) {
    return OcrResult(
      requestId: input.requestId,
      source: input.source,
      status: OcrStatus.emptyText,
      recognizedText: '',
      candidateIssues: candidateIssues,
      completedAt: completedAt,
    );
  }

  factory OcrResult.lowConfidence({
    required OcrInput input,
    required String recognizedText,
    Iterable<OcrTextBlock> blocks = const [],
    OcrConfidence? confidence,
    Iterable<OcrCandidateIssue> candidateIssues = const [],
    DateTime? completedAt,
  }) {
    return OcrResult(
      requestId: input.requestId,
      source: input.source,
      status: OcrStatus.lowConfidence,
      recognizedText: recognizedText,
      blocks: blocks,
      confidence: confidence,
      candidateIssues: candidateIssues,
      completedAt: completedAt,
    );
  }

  factory OcrResult.failed({
    required OcrInput input,
    required OcrFailureReason failureReason,
    String recognizedText = '',
    Iterable<OcrTextBlock> blocks = const [],
    OcrConfidence? confidence,
    Iterable<OcrCandidateIssue> candidateIssues = const [],
    DateTime? completedAt,
  }) {
    return OcrResult(
      requestId: input.requestId,
      source: input.source,
      status: OcrStatus.failed,
      recognizedText: recognizedText,
      blocks: blocks,
      confidence: confidence,
      candidateIssues: candidateIssues,
      failureReason: failureReason,
      completedAt: completedAt,
    );
  }

  factory OcrResult.cancelled({
    required OcrInput input,
    OcrFailureReason? failureReason,
    String recognizedText = '',
    DateTime? completedAt,
  }) {
    return OcrResult(
      requestId: input.requestId,
      source: input.source,
      status: OcrStatus.cancelled,
      recognizedText: recognizedText,
      failureReason: failureReason ??
          const OcrFailureReason(
            code: OcrFailureCodes.cancelled,
            message: '用户取消了 OCR 识别。',
          ),
      completedAt: completedAt,
    );
  }

  factory OcrResult.permissionDenied({
    required OcrInput input,
    OcrFailureReason? failureReason,
    DateTime? completedAt,
  }) {
    return OcrResult(
      requestId: input.requestId,
      source: input.source,
      status: OcrStatus.permissionDenied,
      recognizedText: '',
      failureReason: failureReason ??
          const OcrFailureReason(
            code: OcrFailureCodes.permissionDenied,
            message: '未获得访问原图所需的权限。',
          ),
      completedAt: completedAt,
    );
  }

  factory OcrResult.fromMap(Map<String, Object?> map) {
    final rawBlocks = map['blocks'];
    if (rawBlocks is! List) {
      throw StateError('字段 blocks 不是列表');
    }
    final rawIssues = map['candidate_issues'];
    if (rawIssues is! List) {
      throw StateError('字段 candidate_issues 不是列表');
    }
    final rawConfidence = map['confidence'];
    final rawFailureReason = map['failure_reason'];

    return OcrResult(
      requestId: readOcrString(map, 'request_id'),
      source: OcrImageSource.fromMap(
        readOcrMap(map['source'], 'source'),
      ),
      status: OcrStatus.fromCode(readOcrString(map, 'status')),
      recognizedText: readOcrString(map, 'recognized_text'),
      blocks: rawBlocks.map(
        (item) => OcrTextBlock.fromMap(readOcrMap(item, 'blocks')),
      ),
      confidence: rawConfidence == null
          ? null
          : OcrConfidence.fromMap(readOcrMap(rawConfidence, 'confidence')),
      candidateIssues: rawIssues.map(
        (item) => OcrCandidateIssue.fromMap(
          readOcrMap(item, 'candidate_issues'),
        ),
      ),
      failureReason: rawFailureReason == null
          ? null
          : OcrFailureReason.fromMap(
              readOcrMap(rawFailureReason, 'failure_reason'),
            ),
      completedAt: readOcrNullableDateTime(map, 'completed_at'),
    );
  }

  bool get hasText => recognizedText.trim().isNotEmpty;

  bool get isTerminal => status != OcrStatus.pending;

  bool get isFailure {
    return status == OcrStatus.failed ||
        status == OcrStatus.cancelled ||
        status == OcrStatus.permissionDenied;
  }

  bool get hasBlockingIssues {
    return candidateIssues.any((issue) => issue.isBlocking);
  }

  bool get requiresReview {
    return status == OcrStatus.lowConfidence ||
        candidateIssues.any((issue) => issue.severity != OcrIssueSeverity.info);
  }

  Map<String, Object?> toMap({bool includeEphemeralLocator = false}) {
    return {
      'request_id': requestId,
      'source': source.toMap(
        includeEphemeralLocator: includeEphemeralLocator,
      ),
      'status': status.code,
      'recognized_text': recognizedText,
      'blocks': blocks.map((block) => block.toMap()).toList(),
      'confidence': confidence?.toMap(),
      'candidate_issues': candidateIssues
          .map((issue) => issue.toMap())
          .toList(),
      'failure_reason': failureReason?.toMap(),
      'completed_at': completedAt?.toUtc().toIso8601String(),
    };
  }

  void _validate() {
    if (requestId.trim().isEmpty) {
      throw ArgumentError.value(requestId, 'requestId', 'OCR 请求标识不能为空');
    }
    if (status == OcrStatus.pending && hasText) {
      throw ArgumentError('待处理 OCR 结果不能包含识别文本');
    }
    if (status == OcrStatus.success && !hasText) {
      throw ArgumentError('成功 OCR 结果必须包含识别文本');
    }
    if (status == OcrStatus.emptyText && hasText) {
      throw ArgumentError('空文本 OCR 结果不能包含非空识别文本');
    }
    if (status == OcrStatus.lowConfidence && !hasText) {
      throw ArgumentError('低置信度 OCR 结果必须保留识别文本');
    }
    if (isFailure && failureReason == null) {
      throw ArgumentError('失败、取消或无权限状态必须包含失败原因');
    }
  }
}

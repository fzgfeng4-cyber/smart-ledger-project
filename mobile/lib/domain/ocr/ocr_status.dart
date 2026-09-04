enum OcrStatus {
  pending('pending'),
  success('success'),
  emptyText('empty_text'),
  lowConfidence('low_confidence'),
  failed('failed'),
  cancelled('cancelled'),
  permissionDenied('permission_denied');

  const OcrStatus(this.code);

  final String code;

  static OcrStatus fromCode(String code) {
    final normalized = code.trim();
    for (final status in values) {
      if (status.code == normalized) {
        return status;
      }
    }
    throw ArgumentError.value(code, 'code', '未知 OCR 状态');
  }
}

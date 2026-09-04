import 'dart:convert';

import '../categories/category_catalog.dart';
import '../models/transaction_type.dart';
import '../parser/classification_service.dart';
import '../../shared/clock.dart';
import 'import_contract.dart';

final class AlipayCsvParser {
  const AlipayCsvParser({
    this._classificationService = const ClassificationService(),
    this._clock = const SystemClock(),
  });

  final ClassificationService _classificationService;
  final Clock _clock;

  ImportDraftBatch parse(
    String text, {
    String fileName = 'alipay_bill.csv',
    String? filePath,
    String? charset = 'UTF-8',
  }) {
    ImportLimits.ensureTextWithinLimit(text);
    final records = _AlipayCsvReader(_stripBom(text)).read();
    final header = _findHeader(records);
    final rows = <ImportDraftRow>[];

    for (var index = 0; index < records.length; index += 1) {
      final record = records[index];
      final rawRow = ImportRawRow(
        lineNumber: record.lineNumber,
        rawText: record.rawText,
        fields: record.fields,
      );

      if (header != null && index <= header.recordIndex) {
        continue;
      }
      if (rawRow.isBlank) {
        rows.add(ImportDraftRow(rawRow: rawRow, status: ImportRowStatus.empty));
        continue;
      }
      if (header == null) {
        rows.add(_unknownRow(rawRow, '未找到同时包含支付宝交易时间和金额的表头；未按固定列序猜测，已保留原始内容。'));
        continue;
      }
      if (record.malformed) {
        rows.add(
          _unknownRow(
            rawRow,
            '第 ${rawRow.lineNumber} 行 CSV 引号未正确闭合或位置异常，无法安全映射字段；已保留原始内容。',
          ),
        );
        continue;
      }
      if (record.fields.every((field) => field.trim().isEmpty)) {
        rows.add(_unknownRow(rawRow, '第 ${rawRow.lineNumber} 行只有空字段，未生成交易候选。'));
        continue;
      }

      rows.add(_parseDataRow(rawRow, header.mapping));
    }

    return ImportDraftBatch(
      source: ImportFileSource(
        type: ImportSourceType.alipayCsv,
        fileName: fileName,
        filePath: filePath,
        charset: charset ?? 'UTF-8',
      ),
      originalText: text,
      rows: rows,
    );
  }

  ImportDraftBatch parseBytes(
    List<int> bytes, {
    String fileName = 'alipay_bill.csv',
    String? filePath,
  }) {
    ImportLimits.ensureBytesWithinLimit(bytes.length);
    return parse(
      utf8.decode(bytes),
      fileName: fileName,
      filePath: filePath,
      charset: 'UTF-8',
    );
  }

  ImportDraftBatch parseUtf8(
    List<int> bytes, {
    String fileName = 'alipay_bill.csv',
    String? filePath,
  }) {
    return parseBytes(bytes, fileName: fileName, filePath: filePath);
  }

  _AlipayHeaderMatch? _findHeader(List<_AlipayCsvRecord> records) {
    for (var index = 0; index < records.length && index < 40; index += 1) {
      final record = records[index];
      if (record.malformed) {
        continue;
      }
      final mapping = _AlipayHeaderMapping.fromFields(record.fields);
      if (mapping.hasRequiredFields) {
        return _AlipayHeaderMatch(recordIndex: index, mapping: mapping);
      }
    }
    return null;
  }

  ImportDraftRow _parseDataRow(
    ImportRawRow rawRow,
    _AlipayHeaderMapping mapping,
  ) {
    final rawDate = _cell(rawRow.fields, mapping.indexOf(_AlipayField.date));
    final rawAmount = _cell(
      rawRow.fields,
      mapping.indexOf(_AlipayField.amount),
    );
    final categoryText = _cell(
      rawRow.fields,
      mapping.indexOf(_AlipayField.category),
    );
    final directionText = _cell(
      rawRow.fields,
      mapping.indexOf(_AlipayField.direction),
    );
    final merchant = _cell(
      rawRow.fields,
      mapping.indexOf(_AlipayField.merchant),
    );
    final product = _cell(rawRow.fields, mapping.indexOf(_AlipayField.product));
    final statusText = _cell(
      rawRow.fields,
      mapping.indexOf(_AlipayField.status),
    );
    final transactionId = _cell(
      rawRow.fields,
      mapping.indexOf(_AlipayField.transactionId),
    );
    final merchantOrderId = _cell(
      rawRow.fields,
      mapping.indexOf(_AlipayField.merchantOrderId),
    );
    final extraNote = _cell(rawRow.fields, mapping.indexOf(_AlipayField.note));

    final date = _parseDate(rawDate);
    final amount = _parseAmount(rawAmount);
    final classificationText = _joinNonEmpty([
      categoryText,
      merchant,
      product,
      extraNote,
    ]);
    final status = _parseStatus(
      lineNumber: rawRow.lineNumber,
      categoryText: categoryText,
      product: product,
      statusText: statusText,
    );
    final direction = _resolveDirection(
      directionText: directionText,
      classificationText: classificationText,
      classificationService: _classificationService,
    );
    final isCandidate = status.status == ImportRowStatus.candidate;
    final transactionType = isCandidate ? direction.type : null;
    final issues = <ImportIssue>[];

    if (date.isInvalid) {
      issues.add(
        const ImportIssue(
          code: ImportIssueCodes.invalidDate,
          severity: ImportIssueSeverity.blocking,
          field: 'transaction_date',
          message: '交易时间格式或日期值无效，无法转换为账务日期。',
        ),
      );
    }
    if (amount.isInvalid) {
      issues.add(
        const ImportIssue(
          code: ImportIssueCodes.invalidAmount,
          severity: ImportIssueSeverity.blocking,
          field: 'amount_cents',
          message: '金额格式无法转换为大于 0 的整数分。',
        ),
      );
    }
    if (_isFutureDate(date.value, _clock)) {
      issues.add(
        const ImportIssue(
          code: ImportIssueCodes.futureDate,
          severity: ImportIssueSeverity.blocking,
          field: 'transaction_date',
          message: '账务日期不能是未来日期，请核对后再导入。',
        ),
      );
    }
    if (rawRow.rawText.length > 500) {
      issues.add(
        const ImportIssue(
          code: ImportIssueCodes.rawTextTooLong,
          severity: ImportIssueSeverity.blocking,
          field: 'original_text',
          message: '原始账单行超过 500 个字符，无法安全保存。',
        ),
      );
    }
    if (isCandidate && direction.isAmbiguous) {
      issues.add(
        const ImportIssue(
          code: ImportIssueCodes.unknownDirection,
          severity: ImportIssueSeverity.blocking,
          field: 'type',
          message: '收支字段无法安全判断方向，未默认按支出处理。',
        ),
      );
    } else if (isCandidate && direction.type == null) {
      issues.add(
        const ImportIssue(
          code: ImportIssueCodes.unknownDirection,
          severity: ImportIssueSeverity.blocking,
          field: 'type',
          message: '收支字段为空或无法识别，未默认按支出处理。',
        ),
      );
    }

    final suggestions = <ImportCategorySuggestion>[];
    if (transactionType != null && !direction.isAmbiguous) {
      suggestions.addAll(
        _categorySuggestions(
          type: transactionType,
          classificationText: classificationText,
          categoryText: categoryText,
          product: product,
          extraNote: extraNote,
          issues: issues,
        ),
      );
    }

    if (!isCandidate) {
      issues.add(
        ImportIssue(
          code: _statusRowIssueCode(status.status),
          severity: ImportIssueSeverity.blocking,
          field: 'row',
          message: status.message,
        ),
      );
      if (status.detailIssueCode != null) {
        issues.add(
          ImportIssue(
            code: status.detailIssueCode!,
            severity: ImportIssueSeverity.blocking,
            field: 'status',
            message: status.message,
          ),
        );
      }
    }

    final row = ImportDraftRow(
      rawRow: rawRow,
      status: status.status,
      rawDate: rawDate,
      transactionDate: date.value,
      rawAmount: rawAmount,
      amountCents: amount.value,
      transactionType: transactionType,
      merchant: merchant,
      note: _buildNote(
        merchant: merchant,
        product: product,
        extraNote: extraNote,
        transactionId: transactionId,
        merchantOrderId: merchantOrderId,
      ),
      categorySuggestions: suggestions,
      issues: issues,
    );
    if ((row.ledgerNote?.length ?? 0) > 200) {
      return row.copyWith(
        issues: [
          ...row.issues,
          const ImportIssue(
            code: ImportIssueCodes.noteTooLong,
            severity: ImportIssueSeverity.blocking,
            field: 'note',
            message: '导入备注超过 200 个字符，无法安全保存。',
          ),
        ],
      );
    }
    return row;
  }

  List<ImportCategorySuggestion> _categorySuggestions({
    required TransactionType type,
    required String classificationText,
    required String? categoryText,
    required String? product,
    required String? extraNote,
    required List<ImportIssue> issues,
  }) {
    final candidates = <String>[
      ..._classificationService.categoryCandidates(classificationText),
    ];
    for (final value in [categoryText, product, extraNote]) {
      if (value == null || value.trim().isEmpty) {
        continue;
      }
      final byCode = CategoryCatalog.findByCode(value);
      final bySearch = CategoryCatalog.findBySearchText(value);
      if (byCode != null) {
        candidates.add(byCode.code);
      }
      if (bySearch != null) {
        candidates.add(bySearch.code);
      }
    }

    final uniqueCandidates = _unique(candidates);
    final selection = _classificationService.chooseCategory(
      type: type,
      candidates: uniqueCandidates,
      amountCount: 1,
    );
    final validCandidates = uniqueCandidates
        .where((code) => CategoryCatalog.isValidForType(type, code))
        .toList();
    final orderedCodes = <String>[
      if (selection.code != null) selection.code!,
      ...validCandidates,
    ];
    final uniqueCodes = <String>[];
    for (final code in orderedCodes) {
      if (!CategoryCatalog.isValidForType(type, code) ||
          uniqueCodes.contains(code)) {
        continue;
      }
      uniqueCodes.add(code);
    }

    if (selection.issues.isNotEmpty) {
      issues.add(
        ImportIssue(
          code: ImportIssueCodes.invalidCategory,
          severity: ImportIssueSeverity.warning,
          field: 'category',
          message: selection.issues.first.message,
          candidates: uniqueCodes,
        ),
      );
    }

    return [
      for (final code in uniqueCodes)
        ImportCategorySuggestion(
          categoryCode: code,
          reason: code == selection.code && selection.issues.isNotEmpty
              ? selection.issues.first.message
              : '现有分类规则建议 ${CategoryCatalog.findByCode(code)?.label ?? code}。',
        ),
    ];
  }

  ImportDraftRow _unknownRow(ImportRawRow rawRow, String message) {
    return ImportDraftRow(
      rawRow: rawRow,
      status: ImportRowStatus.unknown,
      issues: [
        ImportIssue(
          code: ImportIssueCodes.unknownRow,
          severity: ImportIssueSeverity.blocking,
          field: 'row',
          message: message,
        ),
      ],
    );
  }
}

enum _AlipayField {
  date,
  category,
  direction,
  amount,
  merchant,
  product,
  status,
  transactionId,
  merchantOrderId,
  note,
}

final class _AlipayHeaderMatch {
  const _AlipayHeaderMatch({required this.recordIndex, required this.mapping});

  final int recordIndex;
  final _AlipayHeaderMapping mapping;
}

final class _AlipayHeaderMapping {
  _AlipayHeaderMapping._(this._indexes);

  final Map<_AlipayField, int> _indexes;

  factory _AlipayHeaderMapping.fromFields(List<String> fields) {
    final indexes = <_AlipayField, int>{};
    for (var index = 0; index < fields.length; index += 1) {
      final field = _alipayHeaderAliases[_normalizeHeader(fields[index])];
      if (field != null) {
        indexes.putIfAbsent(field, () => index);
      }
    }
    return _AlipayHeaderMapping._(indexes);
  }

  bool get hasRequiredFields {
    return _indexes.containsKey(_AlipayField.date) &&
        _indexes.containsKey(_AlipayField.amount);
  }

  int? indexOf(_AlipayField field) => _indexes[field];
}

final class _AlipayCsvRecord {
  const _AlipayCsvRecord({
    required this.lineNumber,
    required this.rawText,
    required this.fields,
    required this.malformed,
  });

  final int lineNumber;
  final String rawText;
  final List<String> fields;
  final bool malformed;
}

final class _AlipayCsvReader {
  const _AlipayCsvReader(this._text);

  final String _text;

  List<_AlipayCsvRecord> read() {
    if (_text.isEmpty) {
      return const [
        _AlipayCsvRecord(
          lineNumber: 1,
          rawText: '',
          fields: [],
          malformed: false,
        ),
      ];
    }

    final records = <_AlipayCsvRecord>[];
    final fields = <String>[];
    final field = StringBuffer();
    final raw = StringBuffer();
    var inQuotes = false;
    var atFieldStart = true;
    var malformed = false;
    var recordStartLine = 1;
    var currentLine = 1;

    void finishRecord() {
      if (records.length >= ImportLimits.maxCsvRecords) {
        throw const ImportInputLimitException('CSV 行数超过 100000 行上限，请拆分账单后重试。');
      }
      fields.add(field.toString());
      records.add(
        _AlipayCsvRecord(
          lineNumber: recordStartLine,
          rawText: raw.toString(),
          fields: List.unmodifiable(fields),
          malformed: malformed || inQuotes,
        ),
      );
      fields.clear();
      field.clear();
      raw.clear();
      inQuotes = false;
      atFieldStart = true;
      malformed = false;
      recordStartLine = currentLine + 1;
    }

    for (var index = 0; index < _text.length; index += 1) {
      final character = _text[index];
      if (inQuotes) {
        raw.write(character);
        if (character == '"') {
          if (index + 1 < _text.length && _text[index + 1] == '"') {
            raw.write('"');
            field.write('"');
            index += 1;
          } else {
            inQuotes = false;
          }
        } else if (character == '\r' || character == '\n') {
          if (character == '\r' &&
              index + 1 < _text.length &&
              _text[index + 1] == '\n') {
            raw.write('\n');
            field.write('\n');
            index += 1;
          } else {
            field.write('\n');
          }
          currentLine += 1;
        } else {
          field.write(character);
        }
        continue;
      }

      if (character == ',') {
        raw.write(character);
        fields.add(field.toString());
        field.clear();
        atFieldStart = true;
        continue;
      }
      if (character == '"' && atFieldStart) {
        raw.write(character);
        inQuotes = true;
        atFieldStart = false;
        continue;
      }
      if (character == '\r' || character == '\n') {
        raw.write(character);
        if (character == '\r' &&
            index + 1 < _text.length &&
            _text[index + 1] == '\n') {
          raw.write('\n');
          index += 1;
        }
        finishRecord();
        currentLine += 1;
        continue;
      }

      raw.write(character);
      field.write(character);
      if (character == '"') {
        malformed = true;
      }
      atFieldStart = false;
    }

    if (raw.isNotEmpty || field.isNotEmpty || fields.isNotEmpty) {
      finishRecord();
    }
    return List.unmodifiable(records);
  }
}

final class _AlipayParsedDate {
  const _AlipayParsedDate({this.value, this.isInvalid = false});

  final String? value;
  final bool isInvalid;
}

final class _AlipayParsedAmount {
  const _AlipayParsedAmount({this.value, this.isInvalid = false});

  final int? value;
  final bool isInvalid;
}

final class _AlipayDirection {
  const _AlipayDirection({this.type, this.isAmbiguous = false});

  final TransactionType? type;
  final bool isAmbiguous;
}

final class _AlipayParsedStatus {
  const _AlipayParsedStatus({
    required this.status,
    required this.message,
    this.detailIssueCode,
  });

  final ImportRowStatus status;
  final String message;
  final String? detailIssueCode;
}

_AlipayParsedDate _parseDate(String? raw) {
  final text = raw?.trim() ?? '';
  if (text.isEmpty) {
    return const _AlipayParsedDate();
  }

  final numeric = RegExp(
    r'^(\d{4})\s*(?:-|/|\.)\s*(\d{1,2})\s*(?:-|/|\.)\s*(\d{1,2})',
  ).firstMatch(text);
  final chinese = RegExp(r'^(\d{4})\s*年\s*(\d{1,2})\s*月\s*(\d{1,2})\s*(?:日|号)?')
      .firstMatch(text);
  final year = int.tryParse(numeric?.group(1) ?? chinese?.group(1) ?? '');
  final month = int.tryParse(numeric?.group(2) ?? chinese?.group(2) ?? '');
  final day = int.tryParse(numeric?.group(3) ?? chinese?.group(3) ?? '');
  if (year == null || month == null || day == null || year < 1) {
    return const _AlipayParsedDate(isInvalid: true);
  }

  final date = DateTime.utc(year, month, day);
  if (date.year != year || date.month != month || date.day != day) {
    return const _AlipayParsedDate(isInvalid: true);
  }
  return _AlipayParsedDate(
    value:
        '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}',
  );
}

_AlipayParsedAmount _parseAmount(String? raw) {
  final text = raw?.trim() ?? '';
  if (text.isEmpty) {
    return const _AlipayParsedAmount();
  }

  final normalized = text
      .replaceAll('¥', '')
      .replaceAll('￥', '')
      .replaceAll('元', '')
      .replaceAll(' ', '')
      .replaceAll('\u00a0', '')
      .replaceAll(',', '')
      .replaceAll('，', '');
  if (!RegExp(r'^\d+(?:\.\d{1,2})?$').hasMatch(normalized)) {
    return const _AlipayParsedAmount(isInvalid: true);
  }

  final parts = normalized.split('.');
  final fraction = parts.length == 2 ? parts[1] : '';
  final cents = BigInt.parse('${parts[0]}${fraction.padRight(2, '0')}');
  if (cents <= BigInt.zero || cents > BigInt.from(9223372036854775807)) {
    return const _AlipayParsedAmount(isInvalid: true);
  }
  return _AlipayParsedAmount(value: cents.toInt());
}

_AlipayParsedStatus _parseStatus({
  required int lineNumber,
  required String? categoryText,
  required String? product,
  required String? statusText,
}) {
  final status = _compact(statusText);
  final context = _joinNonEmpty([categoryText, product, statusText]);
  if (_containsAny(context, const ['退款', '退回', '已退款'])) {
    return _AlipayParsedStatus(
      status: ImportRowStatus.refund,
      message:
          '第 $lineNumber 行包含退款状态或退款类型（${statusText ?? categoryText ?? '退款'}），暂不自动生成入账候选。',
    );
  }
  if (_containsAny(context, const ['不计入账单', '不计入收支', '不计入', '不记账'])) {
    return _AlipayParsedStatus(
      status: ImportRowStatus.failed,
      message: '第 $lineNumber 行资金状态表示不计入账单（${statusText ?? '不计入账单'}），暂不生成入账候选。',
      detailIssueCode: 'non_bookable_status',
    );
  }
  if (_containsAny(status, const [
    '失败',
    '关闭',
    '已关闭',
    '取消',
    '已取消',
    '撤销',
    '已撤销',
    '未支付',
  ])) {
    return _AlipayParsedStatus(
      status: ImportRowStatus.failed,
      message:
          '第 $lineNumber 行资金状态表示交易失败或关闭（${statusText ?? '未知状态'}），暂不生成入账候选。',
    );
  }
  if (status.isEmpty) {
    return _AlipayParsedStatus(
      status: ImportRowStatus.unknown,
      message: '第 $lineNumber 行缺少资金状态，无法确认是否已成功，已保留原始内容。',
      detailIssueCode: 'missing_status',
    );
  }
  if (_containsAny(status, const [
    '交易成功',
    '支付成功',
    '收款成功',
    '转账成功',
    '扣款成功',
    '已支付',
    '已收款',
    '已到账',
    '已完成',
    '成功',
  ])) {
    return const _AlipayParsedStatus(
      status: ImportRowStatus.candidate,
      message: '',
    );
  }
  return _AlipayParsedStatus(
    status: ImportRowStatus.unknown,
    message: '第 $lineNumber 行资金状态“${statusText ?? ''}”无法识别，未默认按普通支出处理；已保留原始内容。',
    detailIssueCode: 'unsupported_status',
  );
}

_AlipayDirection _resolveDirection({
  required String? directionText,
  required String classificationText,
  required ClassificationService classificationService,
}) {
  final explicitDirection = _directionFromText(directionText);
  if (directionText != null && directionText.trim().isNotEmpty) {
    if (explicitDirection == null) {
      return const _AlipayDirection(isAmbiguous: true);
    }
    return _AlipayDirection(type: explicitDirection);
  }

  final incomeHits = classificationService.findIncomeKeywords(
    classificationText,
  );
  final expenseHits = classificationService.findExpenseKeywords(
    classificationText,
  );
  final candidates = [
    ...classificationService.categoryCandidates(classificationText),
    if (CategoryCatalog.findBySearchText(classificationText)
        case final category?)
      category.code,
  ];
  final hasIncomeEvidence =
      incomeHits.isNotEmpty ||
      candidates.any(
        (code) => CategoryCatalog.isValidForType(TransactionType.income, code),
      );
  final hasExpenseEvidence =
      expenseHits.isNotEmpty ||
      candidates.any(
        (code) => CategoryCatalog.isValidForType(TransactionType.expense, code),
      );
  if (hasIncomeEvidence && hasExpenseEvidence) {
    return const _AlipayDirection(isAmbiguous: true);
  }
  if (hasIncomeEvidence) {
    return const _AlipayDirection(type: TransactionType.income);
  }
  if (hasExpenseEvidence) {
    return const _AlipayDirection(type: TransactionType.expense);
  }
  return const _AlipayDirection();
}

TransactionType? _directionFromText(String? raw) {
  final text = _compact(raw);
  if (text.isEmpty) {
    return null;
  }
  if (_containsAny(text, const ['收入', '入账', '收款', '转入', '到账']) ||
      text == '收' ||
      text == '入') {
    return TransactionType.income;
  }
  if (_containsAny(text, const ['支出', '付款', '消费', '转出', '购买']) ||
      text == '支' ||
      text == '出') {
    return TransactionType.expense;
  }
  return null;
}

String? _buildNote({
  required String? merchant,
  required String? product,
  required String? extraNote,
  required String? transactionId,
  required String? merchantOrderId,
}) {
  final parts = <String>[];
  if (product != null && product.isNotEmpty && product != merchant) {
    parts.add(product);
  }
  if (extraNote != null && extraNote.isNotEmpty && !parts.contains(extraNote)) {
    parts.add(extraNote);
  }
  if (transactionId != null && transactionId.isNotEmpty) {
    parts.add('交易单号：$transactionId');
  }
  if (merchantOrderId != null && merchantOrderId.isNotEmpty) {
    parts.add('商户单号：$merchantOrderId');
  }
  return parts.isEmpty ? null : parts.join(' · ');
}

String? _cell(List<String> fields, int? index) {
  if (index == null || index < 0 || index >= fields.length) {
    return null;
  }
  final value = fields[index].trim();
  return value.isEmpty ? null : value;
}

String _joinNonEmpty(Iterable<String?> values) {
  return values
      .where((value) => value != null && value.trim().isNotEmpty)
      .map((value) => value!.trim())
      .join(' ');
}

List<String> _unique(Iterable<String> values) {
  final seen = <String>{};
  return [
    for (final value in values)
      if (seen.add(value)) value,
  ];
}

String _stripBom(String text) {
  return text.startsWith('\uFEFF') ? text.substring(1) : text;
}

String _normalizeHeader(String value) {
  return value
      .replaceAll('\uFEFF', '')
      .trim()
      .toLowerCase()
      .replaceAll('（', '(')
      .replaceAll('）', ')')
      .replaceAll('／', '/')
      .replaceAll(RegExp(r'[\s\u00a0]+'), '');
}

String _compact(String? value) {
  return (value ?? '').trim().replaceAll(RegExp(r'[\s\u00a0]+'), '');
}

bool _containsAny(String text, Iterable<String> values) {
  return values.any(text.contains);
}

bool _isFutureDate(String? value, Clock clock) {
  if (value == null) {
    return false;
  }
  final date = DateTime.tryParse(value);
  if (date == null) {
    return false;
  }
  final now = clock.now();
  final today = DateTime(now.year, now.month, now.day);
  return date.isAfter(today);
}

String _statusRowIssueCode(ImportRowStatus status) {
  return switch (status) {
    ImportRowStatus.unknown => ImportIssueCodes.unknownRow,
    ImportRowStatus.refund => ImportIssueCodes.refundRow,
    ImportRowStatus.failed => ImportIssueCodes.failedRow,
    ImportRowStatus.candidate => '',
    ImportRowStatus.empty => ImportIssueCodes.emptyRow,
  };
}

const _alipayHeaderAliases = <String, _AlipayField>{
  '交易时间': _AlipayField.date,
  '交易日期': _AlipayField.date,
  '账单时间': _AlipayField.date,
  '发生时间': _AlipayField.date,
  '支付时间': _AlipayField.date,
  '日期': _AlipayField.date,
  '时间': _AlipayField.date,
  '交易分类': _AlipayField.category,
  '分类': _AlipayField.category,
  '交易类型': _AlipayField.category,
  '业务类型': _AlipayField.category,
  '类型': _AlipayField.category,
  '收/支': _AlipayField.direction,
  '收支': _AlipayField.direction,
  '收入/支出': _AlipayField.direction,
  '收入支出': _AlipayField.direction,
  '资金方向': _AlipayField.direction,
  '方向': _AlipayField.direction,
  '交易方向': _AlipayField.direction,
  '金额': _AlipayField.amount,
  '金额(元)': _AlipayField.amount,
  '金额(人民币)': _AlipayField.amount,
  '交易金额': _AlipayField.amount,
  '订单金额': _AlipayField.amount,
  '支付金额': _AlipayField.amount,
  '收款金额': _AlipayField.amount,
  '实收金额': _AlipayField.amount,
  '交易对方': _AlipayField.merchant,
  '交易商户': _AlipayField.merchant,
  '商户': _AlipayField.merchant,
  '商户名称': _AlipayField.merchant,
  '对方': _AlipayField.merchant,
  '交易对象': _AlipayField.merchant,
  '收款方': _AlipayField.merchant,
  '付款方': _AlipayField.merchant,
  '对方户名': _AlipayField.merchant,
  '商品说明': _AlipayField.product,
  '商品': _AlipayField.product,
  '商品名称': _AlipayField.product,
  '商品/服务': _AlipayField.product,
  '商品/商户': _AlipayField.product,
  '消费说明': _AlipayField.product,
  '交易描述': _AlipayField.product,
  '摘要': _AlipayField.product,
  '描述': _AlipayField.product,
  '备注': _AlipayField.note,
  '说明': _AlipayField.note,
  '资金说明': _AlipayField.note,
  '资金状态': _AlipayField.status,
  '交易状态': _AlipayField.status,
  '当前状态': _AlipayField.status,
  '账单状态': _AlipayField.status,
  '状态': _AlipayField.status,
  '交易订单号': _AlipayField.transactionId,
  '支付宝订单号': _AlipayField.transactionId,
  '交易单号': _AlipayField.transactionId,
  '订单号': _AlipayField.transactionId,
  '交易号': _AlipayField.transactionId,
  '流水号': _AlipayField.transactionId,
  '商家订单号': _AlipayField.merchantOrderId,
  '商户订单号': _AlipayField.merchantOrderId,
  '商户单号': _AlipayField.merchantOrderId,
};

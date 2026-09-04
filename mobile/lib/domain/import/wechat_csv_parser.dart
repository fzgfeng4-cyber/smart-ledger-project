import 'dart:convert';

import '../categories/category_catalog.dart';
import '../models/transaction_type.dart';
import '../parser/classification_service.dart';
import '../../shared/clock.dart';
import 'import_contract.dart';

final class WechatCsvParser {
  const WechatCsvParser({
    this._classificationService = const ClassificationService(),
    this._clock = const SystemClock(),
  });

  final ClassificationService _classificationService;
  final Clock _clock;

  ImportDraftBatch parse(
    String text, {
    String fileName = 'wechat_bill.csv',
    String? filePath,
    String? charset = 'UTF-8',
  }) {
    ImportLimits.ensureTextWithinLimit(text);
    final records = _CsvReader(_stripBom(text)).read();
    final header = _findHeader(records);
    final rows = <ImportDraftRow>[];

    for (var index = 0; index < records.length; index += 1) {
      final record = records[index];
      final rawRow = ImportRawRow(
        lineNumber: record.lineNumber,
        rawText: record.rawText,
        fields: record.fields,
      );

      if (rawRow.isBlank) {
        rows.add(ImportDraftRow(rawRow: rawRow, status: ImportRowStatus.empty));
        continue;
      }

      if (header == null) {
        rows.add(
          _unknownRow(rawRow, '未找到同时包含交易时间和金额的微信账单表头；未按固定列序猜测，已保留原始内容。'),
        );
        continue;
      }

      if (index <= header.recordIndex) {
        final message = index == header.recordIndex
            ? '检测到 CSV 表头，已保留原始文本但不作为交易候选。'
            : '这是表头前的说明行，已保留原始文本但不作为交易候选。';
        rows.add(_unknownRow(rawRow, message));
        continue;
      }

      if (record.malformed) {
        rows.add(_unknownRow(rawRow, 'CSV 引号未正确闭合或引号位置异常，无法安全映射字段；已保留原始内容。'));
        continue;
      }

      if (record.fields.every((field) => field.trim().isEmpty)) {
        rows.add(_unknownRow(rawRow, '这一行只有空字段，未生成交易候选。'));
        continue;
      }

      rows.add(_parseDataRow(rawRow, header.mapping));
    }

    return ImportDraftBatch(
      source: ImportFileSource(
        type: ImportSourceType.wechatCsv,
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
    String fileName = 'wechat_bill.csv',
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
    String fileName = 'wechat_bill.csv',
    String? filePath,
  }) {
    return parseBytes(bytes, fileName: fileName, filePath: filePath);
  }

  ImportDraftRow _parseDataRow(ImportRawRow rawRow, _HeaderMapping mapping) {
    final rawDate = _cell(rawRow.fields, mapping.indexOf(_HeaderField.date));
    final rawAmount = _cell(
      rawRow.fields,
      mapping.indexOf(_HeaderField.amount),
    );
    final transactionTypeText = _cell(
      rawRow.fields,
      mapping.indexOf(_HeaderField.type),
    );
    final directionText = _cell(
      rawRow.fields,
      mapping.indexOf(_HeaderField.direction),
    );
    final statusText = _cell(
      rawRow.fields,
      mapping.indexOf(_HeaderField.status),
    );
    final merchant = _firstNonEmpty([
      _cell(rawRow.fields, mapping.indexOf(_HeaderField.merchant)),
      _cell(rawRow.fields, mapping.indexOf(_HeaderField.product)),
    ]);
    final product = _cell(rawRow.fields, mapping.indexOf(_HeaderField.product));
    final extraNote = _cell(rawRow.fields, mapping.indexOf(_HeaderField.note));
    final transactionId = _cell(
      rawRow.fields,
      mapping.indexOf(_HeaderField.transactionId),
    );
    final merchantOrderId = _cell(
      rawRow.fields,
      mapping.indexOf(_HeaderField.merchantOrderId),
    );

    final date = _parseDate(rawDate);
    final amount = _parseAmount(rawAmount);
    final status = _parseStatus(
      transactionTypeText: transactionTypeText,
      directionText: directionText,
      statusText: statusText,
    );
    final classificationText = _joinNonEmpty([
      transactionTypeText,
      directionText,
      merchant,
      product,
      extraNote,
    ]);
    final direction = _resolveDirection(
      directionText: directionText,
      transactionTypeText: transactionTypeText,
      classificationText: classificationText,
    );
    final note = _buildNote(
      merchant: merchant,
      product: product,
      extraNote: extraNote,
      transactionId: transactionId,
      merchantOrderId: merchantOrderId,
    );

    final issues = <ImportIssue>[
      if (date.isInvalid)
        const ImportIssue(
          code: ImportIssueCodes.invalidDate,
          severity: ImportIssueSeverity.blocking,
          field: 'transaction_date',
          message: '交易时间格式或日期值无效，无法转换为账务日期。',
        ),
      if (amount.isInvalid)
        const ImportIssue(
          code: ImportIssueCodes.invalidAmount,
          severity: ImportIssueSeverity.blocking,
          field: 'amount_cents',
          message: '金额格式无法转换为大于 0 的整数分。',
        ),
      if (_isFutureDate(date.value, _clock))
        const ImportIssue(
          code: ImportIssueCodes.futureDate,
          severity: ImportIssueSeverity.blocking,
          field: 'transaction_date',
          message: '账务日期不能是未来日期，请核对后再导入。',
        ),
      if (rawRow.rawText.length > 500)
        const ImportIssue(
          code: ImportIssueCodes.rawTextTooLong,
          severity: ImportIssueSeverity.blocking,
          field: 'original_text',
          message: '原始账单行超过 500 个字符，无法安全保存。',
        ),
      if (direction.isAmbiguous)
        const ImportIssue(
          code: ImportIssueCodes.unknownDirection,
          severity: ImportIssueSeverity.blocking,
          field: 'type',
          message: '收支字段和交易类型出现矛盾，无法安全判断方向。',
        ),
      if (!direction.isAmbiguous && direction.type == null)
        const ImportIssue(
          code: ImportIssueCodes.unknownDirection,
          severity: ImportIssueSeverity.blocking,
          field: 'type',
          message: '收支字段为空或无法识别，未默认按支出处理。',
        ),
    ];

    final suggestions = <ImportCategorySuggestion>[];
    if (direction.type != null && !direction.isAmbiguous) {
      final category = _categorySuggestions(
        type: direction.type!,
        classificationText: classificationText,
        issues: issues,
      );
      suggestions.addAll(category.suggestions);
    }

    final rowStatus = status.status;
    if (rowStatus == ImportRowStatus.refund) {
      issues.add(
        ImportIssue(
          code: ImportIssueCodes.refundRow,
          severity: ImportIssueSeverity.blocking,
          field: 'row',
          message: status.message,
        ),
      );
    } else if (rowStatus == ImportRowStatus.failed) {
      issues.add(
        ImportIssue(
          code: ImportIssueCodes.failedRow,
          severity: ImportIssueSeverity.blocking,
          field: 'row',
          message: status.message,
        ),
      );
    }

    final row = ImportDraftRow(
      rawRow: rawRow,
      status: rowStatus,
      rawDate: rawDate,
      transactionDate: date.value,
      rawAmount: rawAmount,
      amountCents: amount.value,
      transactionType: direction.type,
      merchant: merchant,
      note: note,
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

  _CategoryResult _categorySuggestions({
    required TransactionType type,
    required String classificationText,
    required List<ImportIssue> issues,
  }) {
    final candidates = _classificationService.categoryCandidates(
      classificationText,
    );
    final selection = _classificationService.chooseCategory(
      type: type,
      candidates: candidates,
      amountCount: 1,
    );
    final validCandidates = candidates
        .where((code) => CategoryCatalog.isValidForType(type, code))
        .toList();
    final orderedCodes = <String>[
      if (selection.code != null) selection.code!,
      ...validCandidates,
    ];
    final uniqueCodes = <String>[];
    for (final code in orderedCodes) {
      if (!CategoryCatalog.isValidForType(type, code)) {
        continue;
      }
      if (!uniqueCodes.contains(code)) {
        uniqueCodes.add(code);
      }
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

    final suggestions = <ImportCategorySuggestion>[];
    for (final code in uniqueCodes) {
      final label = CategoryCatalog.findByCode(code)?.label ?? code;
      final reason = code == selection.code && selection.issues.isNotEmpty
          ? selection.issues.first.message
          : '现有分类规则建议 $label。';
      suggestions.add(
        ImportCategorySuggestion(categoryCode: code, reason: reason),
      );
    }
    return _CategoryResult(suggestions);
  }

  _HeaderMatch? _findHeader(List<_CsvRecord> records) {
    for (var index = 0; index < records.length && index < 40; index += 1) {
      final record = records[index];
      if (record.malformed) {
        continue;
      }
      final mapping = _HeaderMapping.fromFields(record.fields);
      if (mapping.hasRequiredFields) {
        return _HeaderMatch(recordIndex: index, mapping: mapping);
      }
    }
    return null;
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

typedef WeChatCsvParser = WechatCsvParser;

enum _HeaderField {
  date,
  type,
  direction,
  amount,
  merchant,
  product,
  status,
  transactionId,
  merchantOrderId,
  note,
}

final class _HeaderMatch {
  const _HeaderMatch({required this.recordIndex, required this.mapping});

  final int recordIndex;
  final _HeaderMapping mapping;
}

final class _HeaderMapping {
  _HeaderMapping._(this._indexes);

  final Map<_HeaderField, int> _indexes;

  factory _HeaderMapping.fromFields(List<String> fields) {
    final indexes = <_HeaderField, int>{};
    for (var index = 0; index < fields.length; index += 1) {
      final field = _headerAliases[_normalizeHeader(fields[index])];
      if (field != null) {
        indexes.putIfAbsent(field, () => index);
      }
    }
    return _HeaderMapping._(indexes);
  }

  bool get hasRequiredFields {
    return _indexes.containsKey(_HeaderField.date) &&
        _indexes.containsKey(_HeaderField.amount);
  }

  int? indexOf(_HeaderField field) => _indexes[field];
}

final class _CsvRecord {
  const _CsvRecord({
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

final class _CsvReader {
  const _CsvReader(this._text);

  final String _text;

  List<_CsvRecord> read() {
    if (_text.isEmpty) {
      return const [
        _CsvRecord(lineNumber: 1, rawText: '', fields: [], malformed: false),
      ];
    }

    final records = <_CsvRecord>[];
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
        _CsvRecord(
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
        } else if (character == '\r') {
          field.write(character);
          if (index + 1 < _text.length && _text[index + 1] == '\n') {
            raw.write('\n');
            field.write('\n');
            index += 1;
          }
          currentLine += 1;
        } else if (character == '\n') {
          field.write(character);
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
        if (character == '\r' &&
            index + 1 < _text.length &&
            _text[index + 1] == '\n') {
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

final class _ParsedDate {
  const _ParsedDate({this.value, this.isInvalid = false});

  final String? value;
  final bool isInvalid;
}

final class _ParsedAmount {
  const _ParsedAmount({this.value, this.isInvalid = false});

  final int? value;
  final bool isInvalid;
}

final class _ResolvedDirection {
  const _ResolvedDirection({this.type, this.isAmbiguous = false});

  final TransactionType? type;
  final bool isAmbiguous;
}

final class _ParsedStatus {
  const _ParsedStatus(this.status, this.message);

  final ImportRowStatus status;
  final String message;
}

final class _CategoryResult {
  const _CategoryResult(this.suggestions);

  final List<ImportCategorySuggestion> suggestions;
}

_ParsedDate _parseDate(String? raw) {
  final text = raw?.trim() ?? '';
  if (text.isEmpty) {
    return const _ParsedDate();
  }

  final match = RegExp(
    r'^(\d{4})\s*(?:-|/|\.)\s*(\d{1,2})\s*(?:-|/|\.)\s*(\d{1,2})',
  ).firstMatch(text);
  final chineseMatch = RegExp(
    r'^(\d{4})\s*年\s*(\d{1,2})\s*月\s*(\d{1,2})\s*(?:日|号)?',
  ).firstMatch(text);
  final year = int.tryParse(match?.group(1) ?? chineseMatch?.group(1) ?? '');
  final month = int.tryParse(match?.group(2) ?? chineseMatch?.group(2) ?? '');
  final day = int.tryParse(match?.group(3) ?? chineseMatch?.group(3) ?? '');
  if (year == null || month == null || day == null) {
    return const _ParsedDate(isInvalid: true);
  }

  final date = DateTime(year, month, day);
  if (date.year != year || date.month != month || date.day != day) {
    return const _ParsedDate(isInvalid: true);
  }
  return _ParsedDate(
    value:
        '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}',
  );
}

_ParsedAmount _parseAmount(String? raw) {
  final text = raw?.trim() ?? '';
  if (text.isEmpty) {
    return const _ParsedAmount();
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
    return const _ParsedAmount(isInvalid: true);
  }

  final parts = normalized.split('.');
  final fraction = parts.length == 2 ? parts[1] : '';
  final cents = BigInt.parse('${parts[0]}${fraction.padRight(2, '0')}');
  if (cents <= BigInt.zero || cents > BigInt.from(9223372036854775807)) {
    return const _ParsedAmount(isInvalid: true);
  }
  return _ParsedAmount(value: cents.toInt());
}

_ParsedStatus _parseStatus({
  required String? transactionTypeText,
  required String? directionText,
  required String? statusText,
}) {
  final combined = _joinNonEmpty([
    transactionTypeText,
    directionText,
    statusText,
  ]);
  if (_containsAny(combined, const ['退款', '退回', '已退款'])) {
    return _ParsedStatus(
      ImportRowStatus.refund,
      '这行包含退款状态或退款类型（${statusText?.trim().isNotEmpty == true ? statusText!.trim() : transactionTypeText?.trim() ?? '退款'}），暂不自动生成入账候选。',
    );
  }
  if (_containsAny(combined, const [
    '失败',
    '已关闭',
    '交易关闭',
    '已撤销',
    '已取消',
    '未支付',
    '不计入收支',
  ])) {
    return _ParsedStatus(
      ImportRowStatus.failed,
      '当前状态或交易类型表示失败、关闭或不计入收支（${statusText?.trim().isNotEmpty == true ? statusText!.trim() : transactionTypeText?.trim() ?? '未知状态'}），暂不生成入账候选。',
    );
  }
  return const _ParsedStatus(ImportRowStatus.candidate, '');
}

_ResolvedDirection _resolveDirection({
  required String? directionText,
  required String? transactionTypeText,
  required String classificationText,
}) {
  final directionType = _directionFromText(directionText);
  final transactionType = _directionFromText(transactionTypeText);
  if (directionType != null &&
      transactionType != null &&
      directionType != transactionType) {
    return const _ResolvedDirection(isAmbiguous: true);
  }
  if (directionType != null) {
    return _ResolvedDirection(type: directionType);
  }
  if (transactionType != null) {
    return _ResolvedDirection(type: transactionType);
  }

  final service = const ClassificationService();
  final incomeHits = service.findIncomeKeywords(classificationText);
  final expenseHits = service.findExpenseKeywords(classificationText);
  final candidates = service.categoryCandidates(classificationText);
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
    return const _ResolvedDirection(isAmbiguous: true);
  }
  if (hasIncomeEvidence) {
    return const _ResolvedDirection(type: TransactionType.income);
  }
  if (hasExpenseEvidence) {
    return const _ResolvedDirection(type: TransactionType.expense);
  }
  return const _ResolvedDirection();
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
  if (product != null &&
      product.isNotEmpty &&
      product != merchant &&
      !parts.contains(product)) {
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

String? _firstNonEmpty(Iterable<String?> values) {
  for (final value in values) {
    if (value != null && value.trim().isNotEmpty) {
      return value.trim();
    }
  }
  return null;
}

String _joinNonEmpty(Iterable<String?> values) {
  return values
      .where((value) => value != null && value.trim().isNotEmpty)
      .map((value) => value!.trim())
      .join(' ');
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

final _headerAliases = <String, _HeaderField>{
  '交易时间': _HeaderField.date,
  '交易日期': _HeaderField.date,
  '账单时间': _HeaderField.date,
  '发生时间': _HeaderField.date,
  '支付时间': _HeaderField.date,
  '日期': _HeaderField.date,
  '时间': _HeaderField.date,
  '交易类型': _HeaderField.type,
  '业务类型': _HeaderField.type,
  '类型': _HeaderField.type,
  '交易分类': _HeaderField.type,
  '收/支': _HeaderField.direction,
  '收支': _HeaderField.direction,
  '资金方向': _HeaderField.direction,
  '收入/支出': _HeaderField.direction,
  '方向': _HeaderField.direction,
  '交易方向': _HeaderField.direction,
  '金额(元)': _HeaderField.amount,
  '金额': _HeaderField.amount,
  '交易金额': _HeaderField.amount,
  '订单金额': _HeaderField.amount,
  '支付金额': _HeaderField.amount,
  '收款金额': _HeaderField.amount,
  '交易对方': _HeaderField.merchant,
  '交易商户': _HeaderField.merchant,
  '商户': _HeaderField.merchant,
  '对方': _HeaderField.merchant,
  '交易对象': _HeaderField.merchant,
  '收款方': _HeaderField.merchant,
  '付款方': _HeaderField.merchant,
  '商品': _HeaderField.product,
  '商品说明': _HeaderField.product,
  '商品/服务': _HeaderField.product,
  '商品/商户': _HeaderField.product,
  '消费说明': _HeaderField.product,
  '摘要': _HeaderField.product,
  '交易描述': _HeaderField.product,
  '描述': _HeaderField.product,
  '当前状态': _HeaderField.status,
  '交易状态': _HeaderField.status,
  '资金状态': _HeaderField.status,
  '状态': _HeaderField.status,
  '交易单号': _HeaderField.transactionId,
  '微信订单号': _HeaderField.transactionId,
  '订单号': _HeaderField.transactionId,
  '交易号': _HeaderField.transactionId,
  '商户单号': _HeaderField.merchantOrderId,
  '商户订单号': _HeaderField.merchantOrderId,
  '备注': _HeaderField.note,
};

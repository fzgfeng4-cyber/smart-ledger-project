import '../../shared/clock.dart';
import '../categories/category_catalog.dart';
import '../models/transaction_type.dart';
import 'classification_service.dart';
import 'parse_result.dart';

final class TransactionParser {
  TransactionParser({
    ClassificationService? classificationService,
    Clock? clock,
  }) : _classificationService =
           classificationService ?? const ClassificationService(),
       _clock = clock ?? const SystemClock();

  final ClassificationService _classificationService;
  final Clock _clock;

  ParseResult parse(String text, {DateTime? today}) {
    final originalText = text;
    final parseText = text.trim();
    if (parseText.isEmpty) {
      return ParseResult(
        status: ParseStatus.noDraft,
        originalText: originalText,
        draft: null,
      );
    }

    final todayDate = _dateOnly(today ?? _clock.now());
    final parsedDate = _parseDate(parseText, todayDate);
    final maskedDates = _maskedText(parseText, parsedDate.spans);
    final amountResult = _scanAmounts(parseText, maskedDates);
    final amountMatches = amountResult.matches;

    final issues = <ParseIssue>[...parsedDate.issues];
    int? amountCents;
    if (amountMatches.isEmpty) {
      issues.add(
        ParseIssue(
          code: 'MISSING_AMOUNT',
          field: 'amount_cents',
          message: '缺少金额',
        ),
      );
    } else if (amountMatches.length > 1) {
      issues.add(
        ParseIssue(
          code: 'MULTIPLE_AMOUNTS',
          field: 'amount_cents',
          message: '识别到多个金额，一次只能记一笔账，请拆成两笔记录。',
        ),
      );
    } else if (amountResult.validAmounts.length == 1) {
      amountCents = amountResult.validAmounts.first;
      if (!amountResult.hasUnit) {
        issues.add(
          ParseIssue(
            code: 'BARE_AMOUNT',
            field: 'amount_cents',
            message: '未写元/块，请核对金额。',
          ),
        );
      }
    } else {
      issues.add(
        ParseIssue(
          code: 'INVALID_AMOUNT',
          field: 'amount_cents',
          message: '金额必须大于 0，且最多保留两位小数。',
        ),
      );
    }

    final incomeHits = _classificationService.findIncomeKeywords(parseText);
    final expenseHits = _classificationService.findExpenseKeywords(parseText);
    final categoryCandidates = _classificationService.categoryCandidates(
      parseText,
    );
    final transactionType = _resolveType(
      incomeHits: incomeHits,
      expenseHits: expenseHits,
      categoryCandidates: categoryCandidates,
      issues: issues,
    );

    final categorySelection = _classificationService.chooseCategory(
      type: transactionType,
      candidates: categoryCandidates,
      amountCount: amountMatches.length,
    );
    final category = categorySelection.code;
    issues.addAll(categorySelection.issues);

    if (transactionType != null && category == null) {
      issues.add(
        ParseIssue(
          code: 'MISSING_CATEGORY',
          field: 'category',
          message: '无法确定分类，请选择一个固定分类。',
          candidates: categoryCandidates,
        ),
      );
    }

    final note = _makeNote(
      parseText,
      spans: [...parsedDate.spans, ...amountResult.spans],
    );

    final meaningfulSignal =
        amountMatches.isNotEmpty ||
        incomeHits.isNotEmpty ||
        expenseHits.isNotEmpty ||
        categoryCandidates.isNotEmpty ||
        parsedDate.spans.isNotEmpty ||
        parsedDate.issues.isNotEmpty;
    if (!meaningfulSignal) {
      return ParseResult(
        status: ParseStatus.noDraft,
        originalText: originalText,
        draft: null,
      );
    }

    final missingFields = <String>[];
    if (amountCents == null) {
      missingFields.add('amount_cents');
    }
    if (transactionType == null) {
      missingFields.add('type');
    }
    if (category == null) {
      missingFields.add('category');
    }
    if (parsedDate.date == null) {
      missingFields.add('transaction_date');
    }

    final draft = TransactionDraft(
      amountCents: amountCents,
      type: transactionType,
      category: category,
      note: note,
      originalText: originalText,
      transactionDate: parsedDate.date == null
          ? null
          : formatLocalDate(parsedDate.date!),
    );

    final hasBlockingIssue =
        missingFields.isNotEmpty ||
        parsedDate.isBlocking ||
        issues.any((issue) => issue.isBlocking);
    final status = hasBlockingIssue
        ? ParseStatus.needsInput
        : issues.isNotEmpty
        ? ParseStatus.needsConfirmation
        : ParseStatus.ready;

    return ParseResult(
      status: status,
      originalText: originalText,
      draft: draft,
      missingFields: missingFields,
      issues: issues,
    );
  }

  static TransactionType? _resolveType({
    required List<String> incomeHits,
    required List<String> expenseHits,
    required List<String> categoryCandidates,
    required List<ParseIssue> issues,
  }) {
    final hasIncomeEvidence =
        incomeHits.isNotEmpty ||
        categoryCandidates.any(
          (code) =>
              CategoryCatalog.isValidForType(TransactionType.income, code),
        );
    final hasExpenseEvidence =
        expenseHits.isNotEmpty ||
        categoryCandidates.any(
          (code) =>
              CategoryCatalog.isValidForType(TransactionType.expense, code),
        );

    if (hasIncomeEvidence && hasExpenseEvidence) {
      issues.add(
        ParseIssue(
          code: 'TYPE_CONFLICT',
          field: 'type',
          message: '同时包含收入和支出含义，请改写为一笔账。',
        ),
      );
      return null;
    }
    if (hasIncomeEvidence) {
      return TransactionType.income;
    }
    if (hasExpenseEvidence) {
      return TransactionType.expense;
    }
    issues.add(
      ParseIssue(
        code: 'TYPE_UNKNOWN',
        field: 'type',
        message: '无法判断是收入还是支出，请选择方向。',
      ),
    );
    return null;
  }
}

final class _TextSpan {
  const _TextSpan(this.start, this.end);

  final int start;
  final int end;
}

final class _ParsedDate {
  _ParsedDate({
    required this.date,
    required this.spans,
    required this.issues,
    required this.isBlocking,
  });

  final DateTime? date;
  final List<_TextSpan> spans;
  final List<ParseIssue> issues;
  final bool isBlocking;
}

final class _AmountResult {
  _AmountResult({
    required this.matches,
    required this.validAmounts,
    required this.spans,
    required this.hasUnit,
  });

  final List<RegExpMatch> matches;
  final List<int> validAmounts;
  final List<_TextSpan> spans;
  final bool hasUnit;
}

final _isoDatePattern = RegExp(r'\d{4}-\d{2}-\d{2}');
final _chineseFullDatePattern = RegExp(r'(\d{4})年(\d{1,2})月(\d{1,2})(?:日|号)');
final _chineseMonthDayPattern = RegExp(r'(\d{1,2})月(\d{1,2})(?:日|号)');
final _relativeDatePattern = RegExp(r'今天|昨天|前天');
final _amountPattern = RegExp(r'-?\d+(?:\.\d+)?');

const _maxSqliteInteger = 9223372036854775807;

const _unsupportedDateMarkers = <String>[
  '明天',
  '后天',
  '上周',
  '下周',
  '本周',
  '去年',
  '明年',
  '上个月',
  '下个月',
  '这个月最后',
  '春节前',
];

const _dateTimeWords = <String>['今天', '昨天', '前天', '早上', '上午', '中午', '下午', '晚上'];

const _sentenceSkeletonWords = <String>[
  '支付了',
  '付款了',
  '消费了',
  '花费',
  '花了',
  '支付',
  '付款',
  '消费',
  '支出',
  '记一笔',
  '记账',
  '到账',
];

_ParsedDate _parseDate(String text, DateTime today) {
  final spans = <_TextSpan>[];
  final dateValues = <DateTime?>[];
  final issues = <ParseIssue>[];

  for (final match in _isoDatePattern.allMatches(text)) {
    if (!_hasNumericBoundary(text, match.start, match.end)) {
      continue;
    }
    spans.add(_TextSpan(match.start, match.end));
    dateValues.add(_parseIsoDate(match.group(0)!));
  }

  for (final match in _chineseFullDatePattern.allMatches(text)) {
    final span = _TextSpan(match.start, match.end);
    if (_overlapsAny(span, spans)) {
      continue;
    }
    spans.add(span);
    dateValues.add(
      _strictDate(
        int.parse(match.group(1)!),
        int.parse(match.group(2)!),
        int.parse(match.group(3)!),
      ),
    );
  }

  for (final match in _chineseMonthDayPattern.allMatches(text)) {
    final span = _TextSpan(match.start, match.end);
    if (_overlapsAny(span, spans)) {
      continue;
    }
    spans.add(span);
    dateValues.add(
      _strictDate(
        today.year,
        int.parse(match.group(1)!),
        int.parse(match.group(2)!),
      ),
    );
  }

  for (final match in _relativeDatePattern.allMatches(text)) {
    final span = _TextSpan(match.start, match.end);
    if (_overlapsAny(span, spans)) {
      continue;
    }
    spans.add(span);
    final matchedText = match.group(0);
    if (matchedText == '今天') {
      dateValues.add(today);
    } else if (matchedText == '昨天') {
      dateValues.add(today.subtract(const Duration(days: 1)));
    } else {
      dateValues.add(today.subtract(const Duration(days: 2)));
    }
  }

  if (dateValues.length > 1) {
    issues.add(
      ParseIssue(
        code: 'DATE_AMBIGUOUS',
        field: 'transaction_date',
        message: '识别到多个日期，请只保留一个账务日期。',
      ),
    );
    return _ParsedDate(
      date: null,
      spans: spans,
      issues: issues,
      isBlocking: true,
    );
  }

  if (dateValues.isNotEmpty) {
    final parsedDate = dateValues.first;
    if (parsedDate == null) {
      issues.add(
        ParseIssue(
          code: 'INVALID_DATE',
          field: 'transaction_date',
          message: '日期格式或日期值无效，请改成有效日期。',
        ),
      );
      return _ParsedDate(
        date: null,
        spans: spans,
        issues: issues,
        isBlocking: true,
      );
    }
    if (parsedDate.isAfter(today)) {
      issues.add(
        ParseIssue(
          code: 'FUTURE_DATE',
          field: 'transaction_date',
          message: '这个日期在未来，请检查日期。',
        ),
      );
    }
    return _ParsedDate(
      date: parsedDate,
      spans: spans,
      issues: issues,
      isBlocking: false,
    );
  }

  if (_unsupportedDateMarkers.any(text.contains)) {
    issues.add(
      ParseIssue(
        code: 'UNSUPPORTED_DATE',
        field: 'transaction_date',
        message: '暂不支持这种日期表达，请选择有效的日期。',
      ),
    );
    return _ParsedDate(
      date: null,
      spans: spans,
      issues: issues,
      isBlocking: true,
    );
  }

  return _ParsedDate(
    date: today,
    spans: spans,
    issues: issues,
    isBlocking: false,
  );
}

DateTime? _parseIsoDate(String value) {
  final parts = value.split('-');
  return _strictDate(
    int.parse(parts[0]),
    int.parse(parts[1]),
    int.parse(parts[2]),
  );
}

DateTime? _strictDate(int year, int month, int day) {
  if (month < 1 || month > 12 || day < 1 || day > 31) {
    return null;
  }
  final parsed = DateTime(year, month, day);
  if (parsed.year != year || parsed.month != month || parsed.day != day) {
    return null;
  }
  return parsed;
}

_AmountResult _scanAmounts(String text, String maskedText) {
  final matches = _amountPattern
      .allMatches(maskedText)
      .where((match) => _hasNumericBoundary(maskedText, match.start, match.end))
      .toList();
  final spans = <_TextSpan>[];
  final validAmounts = <int>[];
  var hasUnit = matches.length != 1;

  for (final match in matches) {
    var start = match.start;
    var end = match.end;

    if (text.startsWith('块钱', end)) {
      end += 2;
      hasUnit = true;
    } else if (text.startsWith('元', end) || text.startsWith('块', end)) {
      end += 1;
      hasUnit = true;
    } else if (start > 0) {
      final previous = text.substring(start - 1, start);
      if (previous == '元' || previous == '块') {
        start -= 1;
        hasUnit = true;
      }
    }

    spans.add(_TextSpan(start, end));
    final parsed = _amountToCents(match.group(0)!);
    if (parsed != null) {
      validAmounts.add(parsed);
    }
  }

  return _AmountResult(
    matches: matches,
    validAmounts: validAmounts,
    spans: spans,
    hasUnit: hasUnit,
  );
}

int? _amountToCents(String rawAmount) {
  if (rawAmount.startsWith('-')) {
    return null;
  }

  final parts = rawAmount.split('.');
  if (parts.length > 2 || parts.first.isEmpty || !_isDigits(parts.first)) {
    return null;
  }
  final fractionPart = parts.length == 2 ? parts[1] : '';
  if (fractionPart.length > 2 || !_isDigits(fractionPart)) {
    return null;
  }

  final centsText = '${parts.first}${fractionPart.padRight(2, '0')}';
  final cents = BigInt.parse(centsText);
  if (cents <= BigInt.zero || cents > BigInt.from(_maxSqliteInteger)) {
    return null;
  }
  return cents.toInt();
}

String? _makeNote(String text, {required List<_TextSpan> spans}) {
  var note = _withoutSpans(text, spans);
  for (final word in _dateTimeWords) {
    note = note.replaceAll(word, ' ');
  }
  for (final word in _sentenceSkeletonWords) {
    note = note.replaceAll(word, ' ');
  }
  note = note.replaceAll(RegExp(r'[，,。！？!?；;：:、]+'), ' ');
  note = note.replaceAll(RegExp(r'\s+'), ' ').trim();
  return note.isEmpty ? null : note;
}

String _maskedText(String text, List<_TextSpan> spans) {
  if (spans.isEmpty) {
    return text;
  }
  final buffer = StringBuffer();
  for (var index = 0; index < text.length; index += 1) {
    final masked = spans.any((span) => index >= span.start && index < span.end);
    buffer.write(masked ? ' ' : text[index]);
  }
  return buffer.toString();
}

String _withoutSpans(String text, List<_TextSpan> spans) {
  if (spans.isEmpty) {
    return text;
  }
  final buffer = StringBuffer();
  var cursor = 0;
  for (final span in [
    ...spans,
  ]..sort((left, right) => left.start - right.start)) {
    if (span.start < cursor) {
      continue;
    }
    buffer.write(text.substring(cursor, span.start));
    cursor = span.end.clamp(0, text.length);
  }
  buffer.write(text.substring(cursor));
  return buffer.toString();
}

bool _hasNumericBoundary(String text, int start, int end) {
  final before = start == 0 ? '' : text.substring(start - 1, start);
  final after = end >= text.length ? '' : text.substring(end, end + 1);
  return !_isDigitOrDot(before) && !_isDigitOrDot(after);
}

bool _isDigitOrDot(String value) {
  if (value.isEmpty) {
    return false;
  }
  return value == '.' || RegExp(r'\d').hasMatch(value);
}

bool _isDigits(String value) {
  if (value.isEmpty) {
    return true;
  }
  return RegExp(r'^\d+$').hasMatch(value);
}

bool _overlapsAny(_TextSpan span, List<_TextSpan> spans) {
  return spans.any(
    (existing) => span.start < existing.end && span.end > existing.start,
  );
}

DateTime _dateOnly(DateTime value) {
  return DateTime(value.year, value.month, value.day);
}

import '../../shared/clock.dart';
import 'batch_parse_result.dart';
import 'parse_result.dart';
import 'transaction_parser.dart';

final class MultiTransactionParser {
  MultiTransactionParser({TransactionParser? transactionParser, Clock? clock})
    : _transactionParser = transactionParser ?? TransactionParser(clock: clock),
      _clock = clock ?? const SystemClock();

  final TransactionParser _transactionParser;
  final Clock _clock;

  BatchParseResult parse(String text, {DateTime? today}) {
    final effectiveToday = today ?? _clock.now();
    final lines = _splitIntoLines(text, today: effectiveToday);
    final sharedDate = _sharedDate(text, effectiveToday);
    final transactions = <BatchTransaction>[];
    for (var index = 0; index < lines.length; index += 1) {
      final originalLine = lines[index];
      transactions.add(
        BatchTransaction(
          candidateId: index + 1,
          originalLine: originalLine,
          parseResult: _parseLine(
            originalLine,
            today: effectiveToday,
            sharedDate: sharedDate,
          ),
        ),
      );
    }

    return BatchParseResult(originalText: text, transactions: transactions);
  }

  List<String> _splitIntoLines(String text, {required DateTime today}) {
    final normalized = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final hardSegments = normalized.split(RegExp(r'\n|[，,；;、。！？!?]+'));
    final segments = <String>[];
    for (var index = 0; index < hardSegments.length; index += 1) {
      final segment = hardSegments[index];
      final isEdge = index == 0 || index == hardSegments.length - 1;
      if (segment.trim().isEmpty && isEdge && hardSegments.length > 1) {
        continue;
      }
      segments.addAll(_splitContinuousSegment(segment));
    }
    if (segments.length <= 1) {
      return segments.isEmpty ? [text] : segments;
    }

    final withoutSharedDate = segments
        .where((segment) => !_isStandaloneDateMarker(segment, today))
        .toList();
    return withoutSharedDate.isEmpty ? [text] : withoutSharedDate;
  }

  bool _isStandaloneDateMarker(String segment, DateTime today) {
    final trimmed = segment.trim();
    if (!_dateOnlyPattern.hasMatch(trimmed)) {
      return false;
    }

    final parsed = _transactionParser.parse(trimmed, today: today);
    return parsed.draft?.transactionDate != null;
  }

  ParseResult _parseLine(
    String originalLine, {
    required DateTime today,
    required String? sharedDate,
  }) {
    final result = _transactionParser.parse(
      _removeIdentifierValues(originalLine),
      today: today,
    );
    if (sharedDate == null || _containsDateExpression(originalLine)) {
      return result;
    }

    final draft = result.draft;
    if (draft == null) {
      return result;
    }

    return ParseResult(
      status: result.status,
      originalText: result.originalText,
      draft: TransactionDraft(
        amountCents: draft.amountCents,
        type: draft.type,
        category: draft.category,
        note: draft.note,
        originalText: draft.originalText,
        transactionDate: sharedDate,
      ),
      missingFields: result.missingFields,
      issues: result.issues,
    );
  }

  String? _sharedDate(String text, DateTime today) {
    if (!_containsDateExpression(text)) {
      return null;
    }

    final parsed = _transactionParser.parse(text, today: today).draft;
    return parsed?.transactionDate;
  }

  bool _containsDateExpression(String text) {
    return _datePatterns.any((pattern) => pattern.hasMatch(text)) ||
        _relativeDatePattern.hasMatch(text);
  }

  List<String> _splitContinuousSegment(String segment) {
    final amountMatches = _amountPattern
        .allMatches(segment)
        .where(
          (match) =>
              !_overlapsDate(segment, match.start, match.end) &&
              !_looksLikeIdentifier(segment, match.start),
        )
        .toList();
    if (amountMatches.length <= 1) {
      return [segment];
    }

    final parts = <String>[];
    var start = 0;
    for (var index = 0; index < amountMatches.length - 1; index += 1) {
      final end = amountMatches[index].end;
      final part = segment.substring(start, end);
      if (part.trim().isNotEmpty) {
        parts.add(part);
      }
      start = end;
    }

    final lastPart = segment.substring(start);
    if (lastPart.trim().isNotEmpty) {
      parts.add(lastPart);
    }
    return parts.isEmpty ? [segment] : parts;
  }

  bool _overlapsDate(String text, int start, int end) {
    for (final pattern in _datePatterns) {
      for (final match in pattern.allMatches(text)) {
        if (start < match.end && end > match.start) {
          return true;
        }
      }
    }
    return false;
  }

  bool _looksLikeIdentifier(String text, int start) {
    final prefix = text.substring(0, start);
    return RegExp(
      r'(?:尾号|订单号|交易单号|商户订单号|单号|卡号|流水号|编号|no\.?)\s*$',
      caseSensitive: false,
    ).hasMatch(prefix);
  }

  String _removeIdentifierValues(String text) {
    return text.replaceAllMapped(
      RegExp(
        r'(尾号|订单号|交易单号|商户订单号|单号|卡号|流水号|编号|no\.?)\s*\d+',
        caseSensitive: false,
      ),
      (match) => match.group(1) ?? '',
    );
  }
}

final _amountPattern = RegExp(r'-?\d+(?:\.\d+)?(?:块钱|元|块)?');

final _datePatterns = <RegExp>[
  RegExp(r'\d{4}-\d{2}-\d{2}'),
  RegExp(r'\d{4}年\d{1,2}月\d{1,2}(?:日|号)'),
  RegExp(r'\d{1,2}月\d{1,2}(?:日|号)'),
];

final _relativeDatePattern = RegExp(r'今天|昨天|前天');
final _dateOnlyPattern = RegExp(
  r'^(?:\d{4}-\d{2}-\d{2}|\d{4}年\d{1,2}月\d{1,2}(?:日|号)|\d{1,2}月\d{1,2}(?:日|号)|今天|昨天|前天)$',
);

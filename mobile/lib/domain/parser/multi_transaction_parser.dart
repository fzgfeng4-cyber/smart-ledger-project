import '../../shared/clock.dart';
import 'batch_parse_result.dart';
import 'transaction_parser.dart';

final class MultiTransactionParser {
  MultiTransactionParser({TransactionParser? transactionParser, Clock? clock})
    : _transactionParser = transactionParser ?? TransactionParser(clock: clock),
      _clock = clock ?? const SystemClock();

  final TransactionParser _transactionParser;
  final Clock _clock;

  BatchParseResult parse(String text, {DateTime? today}) {
    final lines = _splitIntoLines(text);
    final transactions = <BatchTransaction>[];
    for (var index = 0; index < lines.length; index += 1) {
      final originalLine = lines[index];
      transactions.add(
        BatchTransaction(
          candidateId: index + 1,
          originalLine: originalLine,
          parseResult: _transactionParser.parse(
            _removeIdentifierValues(originalLine),
            today: today ?? _clock.now(),
          ),
        ),
      );
    }

    return BatchParseResult(originalText: text, transactions: transactions);
  }

  List<String> _splitIntoLines(String text) {
    final normalized = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final hardSegments = normalized.split(RegExp(r'\n|[，,；;、]+'));
    final segments = <String>[];
    for (var index = 0; index < hardSegments.length; index += 1) {
      final segment = hardSegments[index];
      final isEdge = index == 0 || index == hardSegments.length - 1;
      if (segment.trim().isEmpty && isEdge && hardSegments.length > 1) {
        continue;
      }
      segments.addAll(_splitContinuousSegment(segment));
    }
    return segments.isEmpty ? [text] : segments;
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

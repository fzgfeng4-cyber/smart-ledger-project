import '../categories/category_catalog.dart';
import '../models/transaction_type.dart';
import '../parser/classification_service.dart';
import 'local_classification_suggestion.dart';

final class LocalClassificationService {
  const LocalClassificationService();

  static const _classificationService = ClassificationService();

  LocalClassificationSuggestion suggest(String originalText) {
    final text = originalText.trim();
    final ruleHits = <ClassificationRuleHit>[];
    final amount = _parseAmount(text);

    if (amount.matchCount == 1 && amount.amountCents != null) {
      ruleHits.add(
        ClassificationRuleHit(
          ruleId: 'amount_yuan_to_cents',
          field: 'amount',
          matchedText: amount.rawAmount!,
          reason: '本地金额规则将人民币元转换为整数分。',
        ),
      );
    } else if (amount.matchCount > 1) {
      ruleHits.add(
        const ClassificationRuleHit(
          ruleId: 'amount_multiple',
          field: 'amount',
          matchedText: '',
          reason: '识别到多个金额，不能静默选择其中一个。',
        ),
      );
    } else if (amount.rawAmount != null) {
      ruleHits.add(
        ClassificationRuleHit(
          ruleId: 'amount_invalid',
          field: 'amount',
          matchedText: amount.rawAmount!,
          reason: '金额不是大于 0 且最多两位小数的有效金额。',
        ),
      );
    }

    final incomeHits = _classificationService.findIncomeKeywords(text);
    final expenseHits = _classificationService.findExpenseKeywords(text);
    final baseCandidates = _classificationService.categoryCandidates(text);
    final merchantMatches = _findMerchantMatches(text);
    final merchantCandidates = merchantMatches
        .map((match) => match.rule.categoryCode)
        .toList();
    final candidates = _unique([...merchantCandidates, ...baseCandidates]);

    for (final hit in incomeHits) {
      ruleHits.add(
        ClassificationRuleHit(
          ruleId: 'income_keyword',
          field: 'type',
          matchedText: hit,
          reason: '现有本地收入关键词规则建议收入方向。',
        ),
      );
    }
    for (final hit in expenseHits) {
      ruleHits.add(
        ClassificationRuleHit(
          ruleId: 'expense_keyword',
          field: 'type',
          matchedText: hit,
          reason: '现有本地支出关键词规则建议支出方向。',
        ),
      );
    }
    for (final match in merchantMatches) {
      ruleHits.add(
        ClassificationRuleHit(
          ruleId: match.rule.ruleId,
          field: 'category',
          matchedText: match.matchedText,
          reason:
              '本地商户规则将该商户建议为 ${CategoryCatalog.findByCode(match.rule.categoryCode)?.label ?? match.rule.categoryCode}，并建议支出方向。',
        ),
      );
    }
    for (final code in baseCandidates) {
      ruleHits.add(
        ClassificationRuleHit(
          ruleId: 'existing_category_$code',
          field: 'category',
          matchedText: code,
          reason: '现有本地分类规则命中稳定分类 code。',
        ),
      );
    }

    var hasIncomeEvidence =
        incomeHits.isNotEmpty ||
        candidates.any(
          (code) =>
              CategoryCatalog.isValidForType(TransactionType.income, code),
        );
    var hasExpenseEvidence =
        expenseHits.isNotEmpty ||
        candidates.any(
          (code) =>
              CategoryCatalog.isValidForType(TransactionType.expense, code),
        );

    if (!hasIncomeEvidence &&
        !hasExpenseEvidence &&
        _hasDescription(text) &&
        !_classificationService.isRefundText(text) &&
        !_classificationService.isLoanDisbursementText(text)) {
      hasExpenseEvidence = true;
      ruleHits.add(
        const ClassificationRuleHit(
          ruleId: 'default_expense_for_transaction_text',
          field: 'type',
          matchedText: '',
          reason: '存在商户或事项文本但没有收入证据，按消费输入建议支出方向。',
        ),
      );
    }

    TransactionType? type;
    String? categoryCode;
    var isFallback = false;
    final messages = <String>[];

    if (hasIncomeEvidence && hasExpenseEvidence) {
      ruleHits.add(
        const ClassificationRuleHit(
          ruleId: 'direction_conflict',
          field: 'type',
          matchedText: '',
          reason: '收入和支出规则同时命中，不能安全确定收支方向。',
        ),
      );
      messages.add('同时命中收入和支出规则，请确认收支方向。');
    } else if (hasIncomeEvidence) {
      type = TransactionType.income;
    } else if (hasExpenseEvidence) {
      type = TransactionType.expense;
    } else if (_classificationService.isRefundText(text)) {
      messages.add('退款记录不可直接入账，请确认原交易或使用退款处理流程。');
    } else {
      messages.add('无法判断收支方向，请补充商户或事项。');
    }

    if (type != null) {
      final selection = _classificationService.chooseCategory(
        type: type,
        candidates: candidates,
        amountCount: amount.matchCount,
      );
      categoryCode = selection.code;

      if (selection.issues.isNotEmpty) {
        final hasConflict = selection.issues.any(
          (issue) =>
              issue.code == 'CATEGORY_AMBIGUOUS' ||
              issue.code == 'CATEGORY_CONFLICT',
        );
        if (hasConflict) {
          ruleHits.add(
            const ClassificationRuleHit(
              ruleId: 'category_conflict',
              field: 'category',
              matchedText: '',
              reason: '多个分类规则命中，不能静默选择分类。',
            ),
          );
          messages.add('命中多个分类规则，请确认具体分类。');
        } else {
          ruleHits.add(
            ClassificationRuleHit(
              ruleId: 'category_fallback_${categoryCode ?? 'unknown'}',
              field: 'category',
              matchedText: '',
              reason: selection.issues.first.message,
            ),
          );
          messages.add(selection.issues.first.message);
        }
      }

      if (categoryCode == 'other_expense') {
        isFallback = true;
        if (messages.isEmpty) {
          messages.add('无法稳定判断具体分类，已回退到 other_expense（其他支出），请确认。');
        } else if (!messages.any(
          (message) => message.contains('other_expense'),
        )) {
          messages.add('当前分类已回退到 other_expense（其他支出），请确认。');
        }
      } else if (categoryCode == 'other_income') {
        isFallback = true;
        if (messages.isEmpty) {
          messages.add('无法稳定判断具体收入分类，已回退到 other_income（其他收入），请确认。');
        }
      }
    }

    if (amount.matchCount == 0) {
      messages.add('缺少金额，请补充金额。');
    } else if (amount.matchCount > 1) {
      messages.add('识别到多个金额，请一次只输入一笔账。');
    } else if (amount.amountCents == null) {
      messages.add('金额无效，请输入大于 0 且最多两位小数的金额。');
    }

    final canConfirm =
        amount.amountCents != null && type != null && categoryCode != null;
    final status = canConfirm
        ? LocalClassificationSuggestionStatus.needsConfirmation
        : LocalClassificationSuggestionStatus.needsInput;

    return LocalClassificationSuggestion(
      originalText: originalText,
      amountCents: amount.amountCents,
      type: type,
      categoryCode: categoryCode,
      status: status,
      isFallback: isFallback,
      ruleHits: ruleHits,
      message: messages.isEmpty ? null : _unique(messages).join(' '),
    );
  }

  static List<_MerchantMatch> _findMerchantMatches(String text) {
    final normalized = text.toLowerCase();
    final matches = <_MerchantMatch>[];
    for (final rule in _merchantRules) {
      for (final keyword in rule.keywords) {
        final index = normalized.indexOf(keyword.toLowerCase());
        if (index == -1) {
          continue;
        }
        matches.add(
          _MerchantMatch(
            rule: rule,
            matchedText: text.substring(index, index + keyword.length),
          ),
        );
        break;
      }
    }
    return matches;
  }

  static _AmountParseResult _parseAmount(String text) {
    final maskedText = _maskDates(text);
    final matches = _amountPattern
        .allMatches(maskedText)
        .where(
          (match) => _hasNumericBoundary(maskedText, match.start, match.end),
        )
        .toList();

    if (matches.isEmpty) {
      return const _AmountParseResult(matchCount: 0);
    }
    if (matches.length > 1) {
      return _AmountParseResult(matchCount: matches.length);
    }

    final rawAmount = matches.single.group(0)!;
    return _AmountParseResult(
      matchCount: 1,
      rawAmount: rawAmount,
      amountCents: _amountToCents(rawAmount),
    );
  }

  static String _maskDates(String text) {
    return text.replaceAllMapped(
      _datePattern,
      (match) => _spaces(match.group(0)!.length),
    );
  }

  static int? _amountToCents(String rawAmount) {
    if (rawAmount.startsWith('-')) {
      return null;
    }

    final parts = rawAmount.split('.');
    if (parts.length > 2 || parts.first.isEmpty || !_isDigits(parts.first)) {
      return null;
    }
    final fraction = parts.length == 2 ? parts[1] : '';
    if (fraction.length > 2 || !_isDigits(fraction)) {
      return null;
    }

    final cents = BigInt.parse('${parts.first}${fraction.padRight(2, '0')}');
    if (cents <= BigInt.zero || cents > BigInt.from(_maxSqliteInteger)) {
      return null;
    }
    return cents.toInt();
  }

  static bool _hasDescription(String text) {
    var remaining = _maskDates(text).replaceAll(_amountPattern, ' ');
    remaining = remaining.replaceAll(RegExp(r'[\s元块钱，,。！？!?；;：:、/\\-]+'), '');
    return remaining.isNotEmpty;
  }

  static bool _hasNumericBoundary(String text, int start, int end) {
    final before = start == 0 ? '' : text.substring(start - 1, start);
    final after = end >= text.length ? '' : text.substring(end, end + 1);
    return !_isDigitOrDot(before) && !_isDigitOrDot(after);
  }

  static bool _isDigitOrDot(String value) {
    return value == '.' || (value.isNotEmpty && RegExp(r'\d').hasMatch(value));
  }

  static bool _isDigits(String value) {
    return value.isEmpty || RegExp(r'^\d+$').hasMatch(value);
  }

  static String _spaces(int length) {
    return List.filled(length, ' ').join();
  }

  static List<String> _unique(List<String> values) {
    final seen = <String>{};
    return [
      for (final value in values)
        if (seen.add(value)) value,
    ];
  }
}

final class _MerchantRule {
  const _MerchantRule({
    required this.ruleId,
    required this.keywords,
    required this.categoryCode,
  });

  final String ruleId;
  final List<String> keywords;
  final String categoryCode;
}

final class _MerchantMatch {
  const _MerchantMatch({required this.rule, required this.matchedText});

  final _MerchantRule rule;
  final String matchedText;
}

final class _AmountParseResult {
  const _AmountParseResult({
    required this.matchCount,
    this.rawAmount,
    this.amountCents,
  });

  final int matchCount;
  final String? rawAmount;
  final int? amountCents;
}

const _merchantRules = <_MerchantRule>[
  _MerchantRule(
    ruleId: 'merchant_mixue_bingcheng',
    keywords: ['蜜雪冰城'],
    categoryCode: 'dining',
  ),
  _MerchantRule(
    ruleId: 'merchant_sinopec',
    keywords: ['中国石化', '中石化', 'SINOPEC'],
    categoryCode: 'vehicle_fuel',
  ),
];

final _amountPattern = RegExp(r'-?\d+(?:\.\d+)?');
final _datePattern = RegExp(
  r'\d{4}-\d{1,2}-\d{1,2}|\d{4}年\d{1,2}月\d{1,2}(?:日|号)|\d{1,2}月\d{1,2}(?:日|号)',
);

const _maxSqliteInteger = 9223372036854775807;

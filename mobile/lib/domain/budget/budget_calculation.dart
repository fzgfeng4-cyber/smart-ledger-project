import '../../shared/clock.dart';
import '../models/ledger_transaction.dart';
import '../models/transaction_type.dart';
import '../validation/transaction_validator.dart';
import 'budget.dart';
import 'budget_validator.dart';

/// 预算在目标月份内的使用状态。
enum BudgetStatus {
  /// 没有超过预算，包含尚未发生消费的预算。
  withinBudget,

  /// 已使用金额刚好达到预算金额。
  usedUp,

  /// 已使用金额超过预算金额。
  overspent;

  // 这些别名让调用方可以按产品文案选择更贴切的名称，状态值仍保持唯一。
  static const noSpending = withinBudget;
  static const onTrack = withinBudget;
  static const exhausted = usedUp;
  static const overBudget = overspent;
}

/// 单条预算的计算结果。
///
/// 结果只包含派生值，不会回写或修改 [budget]、[transactions] 中的任何对象。
final class BudgetCalculation {
  const BudgetCalculation({
    required this.budget,
    required this.budgetAmountCents,
    required this.usedCents,
    required this.remainingCents,
    required this.overspentCents,
    required this.status,
    required this.estimatedDaysToExhaustion,
  });

  final Budget budget;
  final int budgetAmountCents;
  final int usedCents;
  final int remainingCents;
  final int overspentCents;
  final BudgetStatus status;

  /// 从当前计算日开始，按当前日均支出估算还需多少天用完。
  ///
  /// 没有消费、预算已经用尽或预算为零时返回 null，因为没有可用的正数
  /// 日均支出和未来剩余额度可供预测。
  final int? estimatedDaysToExhaustion;

  String get categoryCode => budget.categoryCode;

  String get month => budget.month;

  int get spentCents => usedCents;

  int get usedAmountCents => usedCents;

  int get amountCents => budgetAmountCents;

  int? get estimatedDays => estimatedDaysToExhaustion;

  int? get estimatedDaysUntilExhausted => estimatedDaysToExhaustion;

  bool get isWithinBudget => status == BudgetStatus.withinBudget;

  bool get isUsedUp => status == BudgetStatus.usedUp;

  bool get isOverspent => status == BudgetStatus.overspent;
}

/// 根据指定月份预算和交易计算预算使用情况。
///
/// 计算规则：
/// - 只累计 `expense`，并排除 [LedgerTransaction.deletedAt] 非空的交易。
/// - 交易按 [LedgerTransaction.transactionDate] 的 `YYYY-MM` 归属月份，并按
///   预算分类 code 匹配。
/// - 当前月份的日均分母是本月已过天数，最小为 1；已完成月份使用该月总天数，
///   未来月份使用 1 天作为防守性分母。
/// - 预计用完天数使用整数分计算并向上取整，最小为 1；无消费、预算为零或
///   已经用尽时不作预测。
/// - 剩余金额和超支金额分别计算，剩余不会为负数。
final class BudgetCalculationService {
  const BudgetCalculationService({Clock? clock})
    : _clock = clock ?? const SystemClock();

  final Clock _clock;

  List<BudgetCalculation> calculate({
    required String month,
    required Iterable<Budget> budgets,
    required Iterable<LedgerTransaction> transactions,
  }) {
    final normalizedMonth = month.trim();
    BudgetValidator.validateMonth(normalizedMonth);

    final now = _clock.now();
    final elapsedDays = _elapsedDaysForMonth(normalizedMonth, now);
    final spentByCategory = _sumExpensesByCategory(
      month: normalizedMonth,
      transactions: transactions,
      today: DateTime(now.year, now.month, now.day),
    );

    return budgets
        .where(
          (budget) => budget.enabled && budget.month.trim() == normalizedMonth,
        )
        .map((budget) {
          final usedCents = spentByCategory[budget.categoryCode] ?? 0;
          final remainingCents = _nonNegativeDifference(
            budget.amountCents,
            usedCents,
          );
          final overspentCents = _nonNegativeDifference(
            usedCents,
            budget.amountCents,
          );
          final status = _status(
            budgetAmountCents: budget.amountCents,
            usedCents: usedCents,
          );

          return BudgetCalculation(
            budget: budget,
            budgetAmountCents: budget.amountCents,
            usedCents: usedCents,
            remainingCents: remainingCents,
            overspentCents: overspentCents,
            status: status,
            estimatedDaysToExhaustion: _estimateDaysToExhaustion(
              budgetAmountCents: budget.amountCents,
              usedCents: usedCents,
              remainingCents: remainingCents,
              elapsedDays: elapsedDays,
            ),
          );
        })
        .toList(growable: false);
  }

  List<BudgetCalculation> calculateForMonth({
    required String month,
    required Iterable<Budget> budgets,
    required Iterable<LedgerTransaction> transactions,
  }) {
    return calculate(
      month: month,
      budgets: budgets,
      transactions: transactions,
    );
  }

  static Map<String, int> _sumExpensesByCategory({
    required String month,
    required Iterable<LedgerTransaction> transactions,
    required DateTime today,
  }) {
    final totals = <String, int>{};
    for (final transaction in transactions) {
      final transactionDate = TransactionValidator.parseTransactionDate(
        transaction.transactionDate,
      );
      if (transaction.isDeleted ||
          transaction.type != TransactionType.expense ||
          transactionDate == null ||
          transactionDate.isAfter(today) ||
          !_belongsToMonth(transactionDate, month)) {
        continue;
      }

      totals.update(
        transaction.category,
        (total) => total + transaction.amountCents,
        ifAbsent: () => transaction.amountCents,
      );
    }
    return totals;
  }

  static bool _belongsToMonth(DateTime transactionDate, String month) {
    final normalizedMonth =
        '${transactionDate.year.toString().padLeft(4, '0')}-'
        '${transactionDate.month.toString().padLeft(2, '0')}';
    return normalizedMonth == month;
  }

  static BudgetStatus _status({
    required int budgetAmountCents,
    required int usedCents,
  }) {
    if (usedCents > budgetAmountCents) {
      return BudgetStatus.overspent;
    }
    if (usedCents == budgetAmountCents) {
      return BudgetStatus.usedUp;
    }
    return BudgetStatus.withinBudget;
  }

  static int _nonNegativeDifference(int minuend, int subtrahend) {
    final difference = minuend - subtrahend;
    return difference < 0 ? 0 : difference;
  }

  static int? _estimateDaysToExhaustion({
    required int budgetAmountCents,
    required int usedCents,
    required int remainingCents,
    required int elapsedDays,
  }) {
    if (budgetAmountCents <= 0 || usedCents <= 0 || remainingCents <= 0) {
      return null;
    }

    // ceil((剩余分 / 已过天数) / (已使用分 / 已过天数)) 的等价整数式。
    final numerator = remainingCents * elapsedDays;
    final days = (numerator + usedCents - 1) ~/ usedCents;
    return days < 1 ? 1 : days;
  }

  static int _elapsedDaysForMonth(String month, DateTime now) {
    final year = int.parse(month.substring(0, 4));
    final monthNumber = int.parse(month.substring(5, 7));
    if (year == now.year && monthNumber == now.month) {
      return now.day < 1 ? 1 : now.day;
    }

    final targetMonth = DateTime(year, monthNumber);
    final currentMonth = DateTime(now.year, now.month);
    if (targetMonth.isBefore(currentMonth)) {
      return DateTime(year, monthNumber + 1, 0).day;
    }
    return 1;
  }
}

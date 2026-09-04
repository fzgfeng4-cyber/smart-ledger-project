import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../ledger_ui_controller.dart';
import '../../domain/budget/budget.dart';
import '../../domain/budget/budget_calculation.dart';
import '../../domain/categories/category_catalog.dart';
import '../../domain/models/transaction_type.dart';
import '../shared/ledger_formatters.dart';

typedef BudgetCreateCallback = void Function(NewBudget budget);
typedef BudgetEditCallback = void Function(Budget budget, BudgetUpdate update);
typedef BudgetDisableCallback = void Function(Budget budget);
typedef BudgetEnableCallback = void Function(Budget budget);
typedef BudgetCreateAsyncCallback = Future<bool> Function(NewBudget budget);
typedef BudgetEditAsyncCallback = Future<bool> Function(
  Budget budget,
  BudgetUpdate update,
);
typedef BudgetDisableAsyncCallback = Future<bool> Function(Budget budget);
typedef BudgetEnableAsyncCallback = Future<bool> Function(Budget budget);

class BudgetPage extends StatefulWidget {
  const BudgetPage({
    required this.month,
    required this.calculations,
    required this.onCreate,
    required this.onEdit,
    required this.onDisable,
    this.onEnable,
    this.onCreateAsync,
    this.onEditAsync,
    this.onDisableAsync,
    this.onEnableAsync,
    this.managedBudgets = const [],
    this.isBusy = false,
    this.feedbackMessage,
    this.errorMessage,
    super.key,
  });

  final String month;
  final List<BudgetCalculation> calculations;
  final BudgetCreateCallback onCreate;
  final BudgetEditCallback onEdit;
  final BudgetDisableCallback onDisable;
  final BudgetEnableCallback? onEnable;
  final BudgetCreateAsyncCallback? onCreateAsync;
  final BudgetEditAsyncCallback? onEditAsync;
  final BudgetDisableAsyncCallback? onDisableAsync;
  final BudgetEnableAsyncCallback? onEnableAsync;
  final List<Budget> managedBudgets;
  final bool isBusy;
  final String? feedbackMessage;
  final String? errorMessage;

  @override
  State<BudgetPage> createState() => _BudgetPageState();
}

class _BudgetPageState extends State<BudgetPage> {
  bool _isOperationInProgress = false;
  String? _localFeedbackMessage;
  String? _localErrorMessage;

  bool get _isBusy => widget.isBusy || _isOperationInProgress;

  @override
  Widget build(BuildContext context) {
    final calculationIds = {
      for (final calculation in widget.calculations) calculation.budget.id,
    };
    final disabledBudgets = widget.managedBudgets
        .where(
          (budget) => !budget.enabled && !calculationIds.contains(budget.id),
        )
        .toList(growable: false);
    final feedbackMessage = widget.feedbackMessage ?? _localFeedbackMessage;
    final errorMessage = widget.errorMessage ?? _localErrorMessage;

    return Scaffold(
      appBar: AppBar(title: const Text('预算')),
      body: SafeArea(
        child: SingleChildScrollView(
          key: const Key('budget-page'),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 112),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _BudgetHeader(
                month: widget.month,
                onCreate: _isBusy ? null : _openCreateForm,
              ),
              if (feedbackMessage != null) ...[
                const SizedBox(height: 12),
                _BudgetFeedbackBanner(message: feedbackMessage, isError: false),
              ],
              if (errorMessage != null) ...[
                const SizedBox(height: 12),
                _BudgetFeedbackBanner(message: errorMessage, isError: true),
              ],
              const SizedBox(height: 20),
              if (widget.calculations.isEmpty && disabledBudgets.isEmpty)
                const _BudgetEmptyState()
              else ...[
                ...widget.calculations.map(
                  (calculation) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _BudgetCard(
                      calculation: calculation,
                      onEdit: _isBusy ? null : () => _openEditForm(calculation),
                      onDisable: calculation.budget.enabled && !_isBusy
                          ? () => _disableBudget(calculation.budget)
                          : null,
                      onEnable: !calculation.budget.enabled && !_isBusy
                          ? () => _enableBudget(calculation.budget)
                          : null,
                    ),
                  ),
                ),
                if (disabledBudgets.isNotEmpty)
                  _BudgetManagementSection(
                    budgets: disabledBudgets,
                    isBusy: _isBusy,
                    onEdit: _openEditBudget,
                    onEnable: _enableBudget,
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openCreateForm() async {
    if (_isBusy) {
      return;
    }
    final result = await _showBudgetForm(
      context,
      title: '新增预算',
      submitLabel: '新增预算',
      initialMonth: widget.month,
    );
    if (!mounted || result == null) {
      return;
    }

    await _createBudget(
      NewBudget(
        categoryCode: result.categoryCode,
        month: result.month,
        amountCents: result.amountCents,
        enabled: result.enabled,
      ),
    );
  }

  Future<void> _openEditForm(BudgetCalculation calculation) async {
    if (_isBusy) {
      return;
    }
    await _openEditBudget(calculation.budget);
  }

  Future<void> _openEditBudget(Budget existing) async {
    if (_isBusy) {
      return;
    }
    final result = await _showBudgetForm(
      context,
      title: '编辑预算',
      submitLabel: '保存修改',
      initialMonth: widget.month,
      existing: existing,
    );
    if (!mounted || result == null) {
      return;
    }

    final update = BudgetUpdate(
      categoryCode: result.categoryCode == existing.categoryCode
          ? null
          : result.categoryCode,
      month: result.month == existing.month ? null : result.month,
      amountCents: result.amountCents == existing.amountCents
          ? null
          : result.amountCents,
      enabled: result.enabled == existing.enabled ? null : result.enabled,
    );
    if (!update.hasChanges) {
      return;
    }
    await _editBudget(existing, update);
  }

  Future<void> _createBudget(NewBudget budget) {
    return _runOperation(
      asyncOperation: widget.onCreateAsync == null
          ? null
          : () => widget.onCreateAsync!(budget),
      syncOperation: () => widget.onCreate(budget),
      successMessage: '预算已保存。',
      errorMessage: '预算保存失败，请重试。',
    );
  }

  Future<void> _editBudget(Budget budget, BudgetUpdate update) {
    return _runOperation(
      asyncOperation: widget.onEditAsync == null
          ? null
          : () => widget.onEditAsync!(budget, update),
      syncOperation: () => widget.onEdit(budget, update),
      successMessage: '预算已更新。',
      errorMessage: '预算更新失败，请重试。',
    );
  }

  Future<void> _disableBudget(Budget budget) {
    return _runOperation(
      asyncOperation: widget.onDisableAsync == null
          ? null
          : () => widget.onDisableAsync!(budget),
      syncOperation: () => widget.onDisable(budget),
      successMessage: '预算已停用。',
      errorMessage: '预算停用失败，请重试。',
    );
  }

  Future<void> _enableBudget(Budget budget) {
    final asyncOperation = widget.onEnableAsync;
    final syncOperation = widget.onEnable;
    if (asyncOperation == null && syncOperation == null) {
      return Future<void>.value();
    }
    return _runOperation(
      asyncOperation: asyncOperation == null
          ? null
          : () => asyncOperation(budget),
      syncOperation: () => syncOperation?.call(budget),
      successMessage: '预算已重新启用。',
      errorMessage: '预算重新启用失败，请重试。',
    );
  }

  Future<void> _runOperation({
    required Future<bool> Function()? asyncOperation,
    required void Function() syncOperation,
    required String successMessage,
    required String errorMessage,
  }) async {
    if (_isBusy) {
      return;
    }

    setState(() {
      _isOperationInProgress = true;
      _localFeedbackMessage = null;
      _localErrorMessage = null;
    });

    var succeeded = true;
    try {
      final operation = asyncOperation;
      if (operation == null) {
        syncOperation();
      } else {
        succeeded = await operation();
      }
    } catch (_) {
      succeeded = false;
    }

    if (!mounted) {
      return;
    }
    setState(() {
      _isOperationInProgress = false;
      if (succeeded) {
        _localFeedbackMessage = successMessage;
      } else {
        _localErrorMessage = errorMessage;
      }
    });
  }
}

class BudgetOverviewPage extends StatefulWidget {
  const BudgetOverviewPage({this.isActive = true, super.key});

  final bool isActive;

  @override
  State<BudgetOverviewPage> createState() => _BudgetOverviewPageState();
}

class _BudgetOverviewPageState extends State<BudgetOverviewPage> {
  List<Budget> _managedBudgets = const [];
  bool _managementBusy = false;
  bool _operationBusy = false;
  bool _operationStarted = false;
  String? _managementError;
  var _managementRequestId = 0;

  @override
  void initState() {
    super.initState();
    _refreshIfActive();
  }

  @override
  void didUpdateWidget(covariant BudgetOverviewPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.isActive && widget.isActive) {
      _refreshIfActive();
    }
  }

  void _refreshIfActive() {
    if (!widget.isActive) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.isActive) {
        unawaited(_refreshPageData());
      }
    });
  }

  Future<void> _refreshPageData() async {
    if (!mounted || !widget.isActive) {
      return;
    }
    final controller = context.read<LedgerUiController>();
    await controller.refreshBudgets();
    if (!mounted || !widget.isActive) {
      return;
    }
    await _refreshManagedBudgets(controller);
  }

  Future<void> _refreshManagedBudgets(LedgerUiController controller) async {
    final requestId = ++_managementRequestId;
    if (mounted) {
      setState(() {
        _managementBusy = true;
        _managementError = null;
      });
    }

    try {
      final budgets = await controller.budgetRepository.listForMonth(
        controller.budgetMonth,
        enabledOnly: false,
      );
      if (!mounted || requestId != _managementRequestId) {
        return;
      }
      setState(() {
        _managedBudgets = budgets;
      });
    } catch (_) {
      if (!mounted || requestId != _managementRequestId) {
        return;
      }
      setState(() {
        _managementError = '预算管理列表加载失败，请重试。';
      });
    } finally {
      if (mounted && requestId == _managementRequestId) {
        setState(() {
          _managementBusy = false;
        });
      }
    }
  }

  Future<bool> _createBudget(NewBudget budget) {
    return _runControllerOperation(
      (controller) => controller.createBudget(budget),
    );
  }

  Future<bool> _editBudget(Budget budget, BudgetUpdate update) {
    return _runControllerOperation(
      (controller) => controller.updateBudget(budget.id, update),
    );
  }

  Future<bool> _disableBudget(Budget budget) {
    return _runControllerOperation(
      (controller) => controller.disableBudget(budget.id),
    );
  }

  Future<bool> _enableBudget(Budget budget) {
    return _runControllerOperation(
      (controller) =>
          controller.updateBudget(budget.id, const BudgetUpdate(enabled: true)),
    );
  }

  Future<bool> _runControllerOperation(
    Future<bool> Function(LedgerUiController) operation,
  ) async {
    if (_operationBusy) {
      return false;
    }
    final controller = context.read<LedgerUiController>();
    setState(() {
      _operationBusy = true;
      _operationStarted = true;
    });

    try {
      final succeeded = await operation(controller);
      await _refreshManagedBudgets(controller);
      return succeeded;
    } finally {
      if (mounted) {
        setState(() {
          _operationBusy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<LedgerUiController>(
      builder: (context, controller, _) {
        final calculations = controller.budgetCalculations;
        final pageError = controller.budgetError ?? _managementError;
        final isBusy =
            controller.isBudgetBusy || _managementBusy || _operationBusy;
        if (controller.isBudgetBusy &&
            calculations.isEmpty &&
            !_operationStarted) {
          return const _BudgetLoadingState();
        }
        if (pageError != null &&
            calculations.isEmpty &&
            _managedBudgets.isEmpty &&
            !_operationStarted &&
            !_managementBusy) {
          return _BudgetErrorState(message: pageError, onRetry: _retry);
        }

        return BudgetPage(
          month: controller.budgetMonth,
          calculations: calculations,
          managedBudgets: _managedBudgets,
          isBusy: isBusy,
          feedbackMessage: controller.budgetFeedback,
          errorMessage: pageError,
          onCreate: (_) {},
          onEdit: (_, _) {},
          onDisable: (_) {},
          onEnable: (_) {},
          onCreateAsync: _createBudget,
          onEditAsync: _editBudget,
          onDisableAsync: _disableBudget,
          onEnableAsync: _enableBudget,
        );
      },
    );
  }

  Future<void> _retry() async {
    final controller = context.read<LedgerUiController>();
    await controller.refreshBudgets();
    if (!mounted || !widget.isActive) {
      return;
    }
    await _refreshManagedBudgets(controller);
  }
}

class _BudgetHeader extends StatelessWidget {
  const _BudgetHeader({required this.month, required this.onCreate});

  final String month;
  final VoidCallback? onCreate;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(
              Icons.calendar_month_outlined,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(width: 8),
            Text(
              '月度预算',
              style: textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          month,
          key: const Key('budget-month-title'),
          style: textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: 48,
          child: FilledButton.icon(
            key: const Key('add-budget-button'),
            onPressed: onCreate,
            icon: const Icon(Icons.add),
            label: const Text('新增预算'),
          ),
        ),
      ],
    );
  }
}

class _BudgetFeedbackBanner extends StatelessWidget {
  const _BudgetFeedbackBanner({required this.message, required this.isError});

  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final backgroundColor = isError
        ? colorScheme.errorContainer
        : colorScheme.secondaryContainer;
    final foregroundColor = isError
        ? colorScheme.onErrorContainer
        : colorScheme.onSecondaryContainer;
    return Semantics(
      liveRegion: true,
      container: true,
      label: message,
      child: Container(
        key: Key(isError ? 'budget-error-banner' : 'budget-feedback-banner'),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              isError ? Icons.error_outline : Icons.check_circle_outline,
              color: foregroundColor,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(message, style: TextStyle(color: foregroundColor)),
            ),
          ],
        ),
      ),
    );
  }
}

class _BudgetEmptyState extends StatelessWidget {
  const _BudgetEmptyState();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      key: const Key('budget-empty-state'),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: const Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('本月还没有预算'),
            SizedBox(height: 6),
            Text('点击“新增预算”开始设置分类额度。'),
          ],
        ),
      ),
    );
  }
}

class _BudgetLoadingState extends StatelessWidget {
  const _BudgetLoadingState();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('预算')),
      body: const SafeArea(
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: CircularProgressIndicator(),
          ),
        ),
      ),
    );
  }
}

class _BudgetErrorState extends StatelessWidget {
  const _BudgetErrorState({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('预算')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.errorContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(message),
                  const SizedBox(height: 8),
                  TextButton.icon(
                    key: const Key('budget-retry'),
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh),
                    label: const Text('重试'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BudgetCard extends StatelessWidget {
  const _BudgetCard({
    required this.calculation,
    required this.onEdit,
    required this.onDisable,
    required this.onEnable,
  });

  final BudgetCalculation calculation;
  final VoidCallback? onEdit;
  final VoidCallback? onDisable;
  final VoidCallback? onEnable;

  @override
  Widget build(BuildContext context) {
    final budget = calculation.budget;
    final colorScheme = Theme.of(context).colorScheme;
    final isOverspent = calculation.isOverspent;
    final category = CategoryCatalog.findByCode(calculation.categoryCode);
    final categoryLabel = category?.label ?? calculation.categoryCode;
    final borderColor = isOverspent
        ? colorScheme.error
        : colorScheme.outlineVariant;

    return Card(
      key: Key('budget-card-${budget.id}'),
      margin: EdgeInsets.zero,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: borderColor),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    categoryLabel,
                    key: Key('budget-category-${budget.id}'),
                    style: Theme.of(context).textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                IconButton(
                  key: Key('budget-edit-${budget.id}'),
                  tooltip: '编辑预算',
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_outlined),
                ),
                if (onDisable != null)
                  IconButton(
                    key: Key('budget-disable-${budget.id}'),
                    tooltip: '停用预算',
                    onPressed: onDisable,
                    icon: const Icon(Icons.pause_circle_outline),
                  ),
                if (onEnable != null)
                  IconButton(
                    key: Key('budget-enable-${budget.id}'),
                    tooltip: '重新启用预算',
                    onPressed: onEnable,
                    icon: const Icon(Icons.play_circle_outline),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            _BudgetStatus(
              calculation: calculation,
              categoryLabel: categoryLabel,
            ),
            const SizedBox(height: 14),
            _BudgetMetrics(calculation: calculation),
            if (calculation.estimatedDaysToExhaustion case final days?) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(
                    Icons.schedule_outlined,
                    size: 18,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '预计用完：$days 天',
                    key: Key('budget-estimated-days-${budget.id}'),
                    style: TextStyle(color: colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _BudgetManagementSection extends StatelessWidget {
  const _BudgetManagementSection({
    required this.budgets,
    required this.isBusy,
    required this.onEdit,
    required this.onEnable,
  });

  final List<Budget> budgets;
  final bool isBusy;
  final Future<void> Function(Budget) onEdit;
  final Future<void> Function(Budget) onEnable;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const Key('disabled-budgets-section'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 8),
        Text(
          '已停用预算',
          key: const Key('disabled-budgets-title'),
          style: Theme.of(context).textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        for (final budget in budgets)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _DisabledBudgetCard(
              budget: budget,
              isBusy: isBusy,
              onEdit: () => onEdit(budget),
              onEnable: () => onEnable(budget),
            ),
          ),
      ],
    );
  }
}

class _DisabledBudgetCard extends StatelessWidget {
  const _DisabledBudgetCard({
    required this.budget,
    required this.isBusy,
    required this.onEdit,
    required this.onEnable,
  });

  final Budget budget;
  final bool isBusy;
  final VoidCallback onEdit;
  final VoidCallback onEnable;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final category = CategoryCatalog.findByCode(budget.categoryCode);
    final categoryLabel = category?.label ?? budget.categoryCode;
    return Card(
      key: Key('budget-card-${budget.id}'),
      margin: EdgeInsets.zero,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    categoryLabel,
                    key: Key('budget-category-${budget.id}'),
                    style: Theme.of(context).textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                IconButton(
                  key: Key('budget-edit-${budget.id}'),
                  tooltip: '编辑预算',
                  onPressed: isBusy ? null : onEdit,
                  icon: const Icon(Icons.edit_outlined),
                ),
                IconButton(
                  key: Key('budget-enable-${budget.id}'),
                  tooltip: '重新启用预算',
                  onPressed: isBusy ? null : onEnable,
                  icon: const Icon(Icons.play_circle_outline),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(
                  Icons.pause_circle_outline,
                  key: Key('budget-status-icon-${budget.id}'),
                  size: 20,
                  color: colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '已停用',
                    key: Key('budget-status-${budget.id}'),
                    style: TextStyle(
                      color: colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  formatMoneyCents(budget.amountCents),
                  key: Key('budget-total-${budget.id}'),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              budget.month,
              key: Key('budget-month-${budget.id}'),
              style: TextStyle(color: colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class _BudgetStatus extends StatelessWidget {
  const _BudgetStatus({required this.calculation, required this.categoryLabel});

  final BudgetCalculation calculation;
  final String categoryLabel;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final status = _statusPresentation(context, calculation);
    return Semantics(
      container: true,
      label: '$categoryLabel预算状态：${status.label}',
      child: Row(
        children: [
          Icon(
            status.icon,
            key: Key('budget-status-icon-${calculation.budget.id}'),
            size: 20,
            color: status.color,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              status.label,
              key: Key('budget-status-${calculation.budget.id}'),
              style: TextStyle(
                color: status.color,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (calculation.isOverspent)
            Text(
              '超支 ${formatMoneyCents(calculation.overspentCents)}',
              key: Key('budget-overspent-${calculation.budget.id}'),
              style: TextStyle(
                color: colorScheme.error,
                fontWeight: FontWeight.w700,
              ),
            ),
        ],
      ),
    );
  }

  _BudgetStatusPresentation _statusPresentation(
    BuildContext context,
    BudgetCalculation calculation,
  ) {
    if (!calculation.budget.enabled) {
      return _BudgetStatusPresentation(
        label: '已停用',
        icon: Icons.pause_circle_outline,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      );
    }
    if (calculation.isOverspent) {
      return _BudgetStatusPresentation(
        label: '已超支',
        icon: Icons.warning_amber_rounded,
        color: Theme.of(context).colorScheme.error,
      );
    }
    if (calculation.isUsedUp) {
      return _BudgetStatusPresentation(
        label: '已用尽',
        icon: Icons.check_circle_outline,
        color: Theme.of(context).colorScheme.tertiary,
      );
    }
    return _BudgetStatusPresentation(
      label: '预算内',
      icon: Icons.check_circle_outline,
      color: Theme.of(context).colorScheme.primary,
    );
  }
}

final class _BudgetStatusPresentation {
  const _BudgetStatusPresentation({
    required this.label,
    required this.icon,
    required this.color,
  });

  final String label;
  final IconData icon;
  final Color color;
}

class _BudgetMetrics extends StatelessWidget {
  const _BudgetMetrics({required this.calculation});

  final BudgetCalculation calculation;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final metrics = [
          _BudgetMetric(
            key: Key('budget-total-${calculation.budget.id}'),
            label: '预算总额',
            amountCents: calculation.budgetAmountCents,
          ),
          _BudgetMetric(
            key: Key('budget-used-${calculation.budget.id}'),
            label: '已使用',
            amountCents: calculation.usedCents,
            amountColor: calculation.isOverspent
                ? Theme.of(context).colorScheme.error
                : null,
          ),
          _BudgetMetric(
            key: Key('budget-remaining-${calculation.budget.id}'),
            label: '剩余',
            amountCents: calculation.remainingCents,
            amountColor: calculation.isOverspent
                ? Theme.of(context).colorScheme.error
                : null,
          ),
        ];

        if (constraints.maxWidth < 440) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var index = 0; index < metrics.length; index += 1) ...[
                if (index > 0) const SizedBox(height: 8),
                _BudgetMetricRow(metric: metrics[index]),
              ],
            ],
          );
        }

        return Row(
          children: [
            for (var index = 0; index < metrics.length; index += 1) ...[
              if (index > 0) const SizedBox(width: 12),
              Expanded(child: metrics[index]),
            ],
          ],
        );
      },
    );
  }
}

class _BudgetMetricRow extends StatelessWidget {
  const _BudgetMetricRow({required this.metric});

  final _BudgetMetric metric;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            metric.label,
            style: Theme.of(context).textTheme.labelLarge,
          ),
        ),
        metric,
      ],
    );
  }
}

class _BudgetMetric extends StatelessWidget {
  const _BudgetMetric({
    required this.label,
    required this.amountCents,
    this.amountColor,
    super.key,
  });

  final String label;
  final int amountCents;
  final Color? amountColor;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 3),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            formatMoneyCents(amountCents),
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(color: amountColor, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}

Future<_BudgetFormValue?> _showBudgetForm(
  BuildContext context, {
  required String title,
  required String submitLabel,
  required String initialMonth,
  Budget? existing,
}) {
  return showModalBottomSheet<_BudgetFormValue>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => _BudgetFormSheet(
      title: title,
      submitLabel: submitLabel,
      initialMonth: initialMonth,
      existing: existing,
    ),
  );
}

class _BudgetFormSheet extends StatefulWidget {
  const _BudgetFormSheet({
    required this.title,
    required this.submitLabel,
    required this.initialMonth,
    this.existing,
  });

  final String title;
  final String submitLabel;
  final String initialMonth;
  final Budget? existing;

  @override
  State<_BudgetFormSheet> createState() => _BudgetFormSheetState();
}

class _BudgetFormSheetState extends State<_BudgetFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _amountController;
  late final TextEditingController _monthController;
  late String? _categoryCode;
  late bool _enabled;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _amountController = TextEditingController(
      text: existing == null ? '' : formatAmountInput(existing.amountCents),
    );
    _monthController = TextEditingController(
      text: existing?.month ?? widget.initialMonth,
    );
    _categoryCode =
        existing != null &&
            CategoryCatalog.isValidForType(
              TransactionType.expense,
              existing.categoryCode,
            )
        ? existing.categoryCode
        : null;
    _enabled = existing?.enabled ?? true;
  }

  @override
  void dispose() {
    _amountController.dispose();
    _monthController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final categories = CategoryCatalog.forType(TransactionType.expense);
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Material(
        color: colorScheme.surface,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.9,
          ),
          child: SingleChildScrollView(
            key: const Key('budget-form-scroll'),
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Form(
              key: _formKey,
              autovalidateMode: AutovalidateMode.onUserInteraction,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          widget.title,
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                      IconButton(
                        key: const Key('budget-form-close'),
                        tooltip: '关闭',
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    key: const Key('budget-amount-field'),
                    controller: _amountController,
                    decoration: const InputDecoration(
                      labelText: '预算金额',
                      hintText: '例如 300.00',
                      suffixText: '元',
                      filled: true,
                    ),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    textInputAction: TextInputAction.next,
                    validator: _validateAmount,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    key: const Key('budget-month-field'),
                    controller: _monthController,
                    decoration: const InputDecoration(
                      labelText: '月份',
                      hintText: 'YYYY-MM',
                      filled: true,
                    ),
                    keyboardType: TextInputType.datetime,
                    textInputAction: TextInputAction.next,
                    validator: _validateMonth,
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    key: const Key('budget-category-field'),
                    initialValue: _categoryCode,
                    decoration: const InputDecoration(
                      labelText: '支出分类',
                      filled: true,
                    ),
                    items: categories
                        .map(
                          (category) => DropdownMenuItem<String>(
                            value: category.code,
                            child: Text(category.label),
                          ),
                        )
                        .toList(growable: false),
                    onChanged: (value) {
                      setState(() => _categoryCode = value);
                    },
                    validator: (value) {
                      if (value == null ||
                          !CategoryCatalog.isValidForType(
                            TransactionType.expense,
                            value,
                          )) {
                        return '请选择支出分类';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 4),
                  SwitchListTile(
                    key: const Key('budget-enabled-field'),
                    contentPadding: EdgeInsets.zero,
                    title: const Text('启用预算'),
                    subtitle: Text(
                      _enabled ? '会参与当前月份预算提醒' : '停用后保留记录，但不再作为启用预算',
                    ),
                    value: _enabled,
                    onChanged: (value) => setState(() => _enabled = value),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 48,
                    child: FilledButton.icon(
                      key: const Key('budget-form-submit'),
                      onPressed: _isSubmitting ? null : _submit,
                      icon: const Icon(Icons.check),
                      label: Text(widget.submitLabel),
                    ),
                  ),
                  const SizedBox(height: 4),
                  SizedBox(
                    height: 48,
                    child: TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('取消'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _submit() {
    if (_isSubmitting) {
      return;
    }
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final categoryCode = _categoryCode;
    final amountCents = parseYuanToCents(_amountController.text);
    if (categoryCode == null || amountCents == null) {
      return;
    }

    setState(() => _isSubmitting = true);
    Navigator.of(context).pop(
      _BudgetFormValue(
        categoryCode: categoryCode,
        month: _monthController.text.trim(),
        amountCents: amountCents,
        enabled: _enabled,
      ),
    );
  }

  String? _validateAmount(String? value) {
    if (parseYuanToCents(value ?? '') == null) {
      return '请输入大于 0 的有效金额（元）';
    }
    return null;
  }

  String? _validateMonth(String? value) {
    final normalized = value?.trim() ?? '';
    final match = _monthPattern.firstMatch(normalized);
    if (match == null) {
      return '月份格式必须是 YYYY-MM';
    }

    final year = int.parse(match.group(1)!);
    final month = int.parse(match.group(2)!);
    if (year == 0 || month < 1 || month > 12) {
      return '请输入有效月份（YYYY-MM）';
    }
    return null;
  }
}

final class _BudgetFormValue {
  const _BudgetFormValue({
    required this.categoryCode,
    required this.month,
    required this.amountCents,
    required this.enabled,
  });

  final String categoryCode;
  final String month;
  final int amountCents;
  final bool enabled;
}

final _monthPattern = RegExp(r'^(\d{4})-(\d{2})$');

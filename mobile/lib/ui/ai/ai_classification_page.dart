import 'package:flutter/material.dart';

import '../../domain/categories/category_catalog.dart';
import '../../domain/classification/local_classification_service.dart';
import '../../domain/classification/local_classification_suggestion.dart';
import '../../domain/models/transaction_type.dart';
import '../../ui/shared/ledger_formatters.dart';

typedef AiClassificationConfirmationHandler = Future<bool> Function(
  String input, {
  required TransactionType type,
  required String categoryCode,
});

class AiClassificationPage extends StatefulWidget {
  const AiClassificationPage({
    required this.today,
    required this.onContinueToConfirmation,
    super.key,
  });

  final DateTime today;
  final AiClassificationConfirmationHandler onContinueToConfirmation;

  @override
  State<AiClassificationPage> createState() => _AiClassificationPageState();
}

class _AiClassificationPageState extends State<AiClassificationPage> {
  final _inputController = TextEditingController();
  static const _service = LocalClassificationService();

  LocalClassificationSuggestion? _suggestion;
  String? _selectedCategory;
  String? _statusMessage;
  String? _errorMessage;
  bool _confirmedSuggestion = false;
  bool _isOpeningConfirmation = false;

  bool get _hasUnsavedInput => _inputController.text.trim().isNotEmpty;

  @override
  void dispose() {
    _inputController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final suggestion = _suggestion;
    final type = suggestion?.type;
    final categoryCode = _selectedCategory ?? suggestion?.categoryCode;
    final canContinue =
        suggestion?.needsConfirmation == true &&
        type != null &&
        categoryCode != null &&
        _confirmedSuggestion &&
        !_isOpeningConfirmation;

    return PopScope<Object?>(
      canPop: !_isOpeningConfirmation && !_hasUnsavedInput,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          _handleBack();
        }
      },
      child: Scaffold(
        key: const Key('ai-classification-page'),
        appBar: AppBar(
          leading: IconButton(
            key: const Key('ai-back'),
            tooltip: '返回',
            onPressed: _isOpeningConfirmation ? null : _handleBack,
            icon: const Icon(Icons.arrow_back),
          ),
          title: const Text('AI 分类输入'),
        ),
        body: SafeArea(
          child: CustomScrollView(
            key: const Key('ai-classification-scroll'),
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 180),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    TextField(
                      key: const Key('ai-classification-input'),
                      controller: _inputController,
                      onChanged: _handleInputChanged,
                      textInputAction: TextInputAction.done,
                      decoration: const InputDecoration(
                        labelText: '输入一笔账',
                        hintText: '例如：蜜雪冰城 12',
                        prefixIcon: Icon(Icons.auto_awesome),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ActionChip(
                          key: const Key('ai-example-mixue'),
                          avatar: const Icon(Icons.local_drink_outlined),
                          label: const Text('蜜雪冰城 12'),
                          onPressed: () => _useExample('蜜雪冰城 12'),
                        ),
                        ActionChip(
                          key: const Key('ai-example-sinopec'),
                          avatar: const Icon(Icons.local_gas_station_outlined),
                          label: const Text('中国石化300'),
                          onPressed: () => _useExample('中国石化300'),
                        ),
                      ],
                    ),
                    if (suggestion == null &&
                        _inputController.text.trim().isEmpty) ...[
                      const SizedBox(height: 28),
                      const _AiEmptyState(),
                    ],
                    if (suggestion != null) ...[
                      const SizedBox(height: 20),
                      _SuggestionPanel(
                        suggestion: suggestion,
                        selectedCategory: categoryCode,
                        onCategorySelected: _selectCategory,
                      ),
                      if (suggestion.needsConfirmation) ...[
                        const SizedBox(height: 14),
                        CheckboxListTile(
                          key: const Key('ai-confirm-suggestion'),
                          contentPadding: EdgeInsets.zero,
                          value: _confirmedSuggestion,
                          onChanged: _isOpeningConfirmation
                              ? null
                              : (value) {
                                  setState(() {
                                    _confirmedSuggestion = value ?? false;
                                  });
                                },
                          title: const Text('我已核对金额、收支和分类建议'),
                          subtitle: const Text('确认后进入账目详情，保存前仍可修改。'),
                          controlAffinity: ListTileControlAffinity.leading,
                        ),
                      ],
                    ],
                    if (_errorMessage != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        _errorMessage!,
                        key: const Key('ai-error-message'),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                    if (_statusMessage != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        _statusMessage!,
                        key: const Key('ai-status-message'),
                      ),
                    ],
                  ]),
                ),
              ),
            ],
          ),
        ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: FilledButton.icon(
              key: const Key('ai-confirm-button'),
              onPressed: canContinue ? _continueToConfirmation : null,
              icon: _isOpeningConfirmation
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.arrow_forward),
              label: Text(_isOpeningConfirmation ? '确认中...' : '进入账目确认'),
            ),
          ),
        ),
      ),
    );
  }

  void _handleInputChanged(String value) {
    final normalized = value.trim();
    setState(() {
      _suggestion = normalized.isEmpty ? null : _service.suggest(value);
      _selectedCategory = _suggestion?.categoryCode;
      _confirmedSuggestion = false;
      _statusMessage = null;
      _errorMessage = null;
    });
  }

  void _useExample(String value) {
    _inputController
      ..text = value
      ..selection = TextSelection.collapsed(offset: value.length);
    _handleInputChanged(value);
  }

  void _selectCategory(String code) {
    setState(() {
      _selectedCategory = code;
      _confirmedSuggestion = false;
      _statusMessage = null;
    });
  }

  Future<void> _continueToConfirmation() async {
    final suggestion = _suggestion;
    final type = suggestion?.type;
    final categoryCode = _selectedCategory ?? suggestion?.categoryCode;
    final input = _inputController.text.trim();
    if (suggestion == null ||
        !suggestion.needsConfirmation ||
        type == null ||
        categoryCode == null ||
        input.isEmpty ||
        _isOpeningConfirmation) {
      return;
    }

    setState(() {
      _isOpeningConfirmation = true;
      _errorMessage = null;
      _statusMessage = null;
    });

    try {
      final completed = await widget.onContinueToConfirmation(
        input,
        type: type,
        categoryCode: categoryCode,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _isOpeningConfirmation = false;
        if (completed) {
          _inputController.clear();
          _suggestion = null;
          _selectedCategory = null;
          _confirmedSuggestion = false;
          _statusMessage = '账目已保存。';
        } else {
          _statusMessage = '已取消确认，账本未修改。';
        }
      });
    } on Object catch (_) {
      if (mounted) {
        setState(() {
          _isOpeningConfirmation = false;
          _errorMessage = '无法进入账目确认，请重试。';
        });
      }
    }
  }

  Future<void> _handleBack() async {
    if (!_hasUnsavedInput) {
      if (mounted) {
        Navigator.of(context).pop();
      }
      return;
    }

    final shouldDiscard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        key: const Key('ai-discard-dialog'),
        title: const Text('放弃输入？'),
        content: const Text('这笔账还没有确认保存。'),
        actions: [
          TextButton(
            key: const Key('ai-continue-editing'),
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('继续编辑'),
          ),
          FilledButton(
            key: const Key('ai-discard-input'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('放弃输入'),
          ),
        ],
      ),
    );

    if (shouldDiscard == true && mounted) {
      _inputController.clear();
      Navigator.of(context).pop();
    }
  }
}

class _AiEmptyState extends StatelessWidget {
  const _AiEmptyState();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      key: const Key('ai-empty-state'),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Padding(
        padding: EdgeInsets.all(20),
        child: Column(
          children: [
            Icon(Icons.auto_awesome, size: 42),
            SizedBox(height: 10),
            Text('输入商户和金额，查看本地分类建议。'),
          ],
        ),
      ),
    );
  }
}

class _SuggestionPanel extends StatelessWidget {
  const _SuggestionPanel({
    required this.suggestion,
    required this.selectedCategory,
    required this.onCategorySelected,
  });

  final LocalClassificationSuggestion suggestion;
  final String? selectedCategory;
  final ValueChanged<String> onCategorySelected;

  @override
  Widget build(BuildContext context) {
    final type = suggestion.type;
    final categoryCode = selectedCategory ?? suggestion.categoryCode;
    final categories = type == null
        ? const <CategoryDefinition>[]
        : CategoryCatalog.forType(type);

    return DecoratedBox(
      key: const Key('ai-suggestion-panel'),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '分类建议',
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            if (suggestion.amountCents != null)
              _SuggestionValue(
                label: '金额',
                value: formatMoneyCents(suggestion.amountCents!),
              ),
            if (type != null)
              _SuggestionValue(
                label: '收支',
                value: type == TransactionType.expense ? '支出' : '收入',
              ),
            if (categoryCode != null)
              _SuggestionValue(
                label: '分类',
                value:
                    CategoryCatalog.findByCode(categoryCode)?.label ??
                    categoryCode,
              ),
            if (suggestion.message != null) ...[
              const SizedBox(height: 10),
              Text(suggestion.message!),
            ],
            if (categories.isNotEmpty) ...[
              const SizedBox(height: 14),
              Text('可选分类', style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final category in categories)
                    ChoiceChip(
                      key: Key('ai-category-${category.code}'),
                      label: Text(category.label),
                      selected: category.code == categoryCode,
                      onSelected: (_) => onCategorySelected(category.code),
                    ),
                ],
              ),
            ],
            if (!suggestion.needsConfirmation) ...[
              const SizedBox(height: 10),
              Text(
                suggestion.message ?? '请补充金额、商户或收支信息。',
                key: const Key('ai-needs-input'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SuggestionValue extends StatelessWidget {
  const _SuggestionValue({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(
            width: 52,
            child: Text(label, style: Theme.of(context).textTheme.labelLarge),
          ),
          Expanded(
            child: Text(value, style: Theme.of(context).textTheme.bodyLarge),
          ),
        ],
      ),
    );
  }
}

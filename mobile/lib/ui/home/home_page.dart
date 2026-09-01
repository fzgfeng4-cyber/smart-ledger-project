import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/app_routes.dart';
import '../ledger_ui_controller.dart';
import '../shared/ui_components.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late final TextEditingController _quickInputController;

  @override
  void initState() {
    super.initState();
    _quickInputController = TextEditingController();
  }

  @override
  void dispose() {
    _quickInputController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<LedgerUiController>(
      builder: (context, controller, _) {
        final recentEntries = controller.recentEntries;
        return SafeArea(
          child: CustomScrollView(
            key: const Key('home-page'),
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 96),
                sliver: SliverList(
                  delegate: SliverChildListDelegate.fixed([
                    const AppTopBar(title: 'Smart Ledger'),
                    const SizedBox(height: 16),
                    _StatsRow(controller: controller),
                    const SizedBox(height: 18),
                    _QuickInputCard(
                      textController: _quickInputController,
                      errorText: controller.quickInputError,
                    ),
                    const SizedBox(height: 22),
                    SectionHeader(
                      title: '最近账目',
                      action: TextButton.icon(
                        key: const Key('view-all-transactions'),
                        onPressed: () =>
                            Navigator.of(context)
                                .pushReplacementNamed(AppRoutes.transactions),
                        icon: const Icon(Icons.receipt_long),
                        label: const Text('查看全部'),
                      ),
                    ),
                    const SizedBox(height: 8),
                    const UndoDeleteBanner(),
                    if (recentEntries.isEmpty)
                      const _HomeEmptyState()
                    else
                      ...recentEntries.map(
                        (entry) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: TransactionTile(
                            entry: entry,
                            today: controller.today,
                            onTap: () {
                              controller.startEditing(entry);
                              Navigator.of(context)
                                  .pushNamed(AppRoutes.editTransaction);
                            },
                          ),
                        ),
                      ),
                  ]),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _StatsRow extends StatelessWidget {
  const _StatsRow({required this.controller});

  final LedgerUiController controller;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: StatCard(
            label: '今天支出',
            amountCents: controller.todayExpenseCents,
            icon: Icons.today,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: StatCard(
            label: '本月支出',
            amountCents: controller.monthExpenseCents,
            icon: Icons.calendar_month,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: StatCard(
            label: '本月收入',
            amountCents: controller.monthIncomeCents,
            icon: Icons.payments,
          ),
        ),
      ],
    );
  }
}

class _QuickInputCard extends StatelessWidget {
  const _QuickInputCard({
    required this.textController,
    required this.errorText,
  });

  final TextEditingController textController;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    final controller = context.read<LedgerUiController>();
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '快速记账',
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            LayoutBuilder(
              builder: (context, constraints) {
                final input = TextField(
                  key: const Key('quick-input'),
                  controller: textController,
                  textInputAction: TextInputAction.done,
                  minLines: 1,
                  maxLines: 3,
                  decoration: InputDecoration(
                    hintText: '例如：35块买菜',
                    errorText: errorText,
                    filled: true,
                  ),
                  onSubmitted: (_) => _submit(context, controller),
                );
                final button = FilledButton.icon(
                  key: const Key('quick-submit'),
                  onPressed: () => _submit(context, controller),
                  icon: const Icon(Icons.arrow_forward),
                  label: const Text('识别'),
                );

                if (constraints.maxWidth < 420) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      input,
                      const SizedBox(height: 10),
                      SizedBox(height: 48, child: button),
                    ],
                  );
                }

                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: input),
                    const SizedBox(width: 10),
                    SizedBox(width: 104, height: 56, child: button),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  void _submit(BuildContext context, LedgerUiController controller) {
    final prepared = controller.prepareDraftFromInput(textController.text);
    if (prepared) {
      FocusManager.instance.primaryFocus?.unfocus();
      Navigator.of(context).pushNamed(AppRoutes.newTransaction);
    }
  }
}

class _HomeEmptyState extends StatelessWidget {
  const _HomeEmptyState();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      key: const Key('home-empty-state'),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('还没有账目'),
            SizedBox(height: 6),
            Text('输入第一笔，例如“35块买菜”。'),
          ],
        ),
      ),
    );
  }
}

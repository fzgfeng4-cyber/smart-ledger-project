import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/app_routes.dart';
import '../ledger_ui_controller.dart';
import '../models/ledger_ui_models.dart';
import '../shared/ui_components.dart';

class TransactionsPage extends StatelessWidget {
  const TransactionsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<LedgerUiController>(
      builder: (context, controller, _) {
        final entries = controller.visibleEntries;
        return SafeArea(
          child: CustomScrollView(
            key: const Key('transactions-page'),
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 96),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    AppTopBar(
                      title: '账单',
                      trailing: TextButton.icon(
                        key: const Key('new-transaction-from-list'),
                        onPressed: () {
                          controller.startCreateBlank();
                          Navigator.of(context)
                              .pushNamed(AppRoutes.newTransaction);
                        },
                        icon: const Icon(Icons.add),
                        label: const Text('记一笔'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const UndoDeleteBanner(),
                    if (controller.listStatus == LedgerListStatus.loading &&
                        entries.isEmpty)
                      const Center(
                        key: Key('transactions-initial-loading'),
                        child: Padding(
                          padding: EdgeInsets.all(16),
                          child: CircularProgressIndicator(),
                        ),
                      )
                    else if (controller.listStatus == LedgerListStatus.error &&
                        entries.isEmpty)
                      const _ListErrorState()
                    else if (entries.isEmpty)
                      const _TransactionsEmptyState()
                    else
                      ..._buildEntries(context, controller, entries),
                    const SizedBox(height: 12),
                    _LoadMoreFooter(controller: controller),
                  ]),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  List<Widget> _buildEntries(
    BuildContext context,
    LedgerUiController controller,
    List<UiLedgerEntry> entries,
  ) {
    final widgets = <Widget>[];
    String? currentDate;
    for (final entry in entries) {
      if (entry.transactionDate != currentDate) {
        currentDate = entry.transactionDate;
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(top: 10, bottom: 8),
            child: Text(
              currentDate,
              style: Theme.of(context).textTheme.labelLarge,
            ),
          ),
        );
      }
      widgets.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: TransactionTile(
            entry: entry,
            today: controller.today,
            onTap: () {
              controller.startEditing(entry);
              Navigator.of(context).pushNamed(AppRoutes.editTransaction);
            },
          ),
        ),
      );
    }
    return widgets;
  }
}

class _TransactionsEmptyState extends StatelessWidget {
  const _TransactionsEmptyState();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      key: const Key('transactions-empty-state'),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('还没有账单'),
            SizedBox(height: 6),
            Text('记一笔后会按日期显示在这里。'),
          ],
        ),
      ),
    );
  }
}

class _ListErrorState extends StatelessWidget {
  const _ListErrorState();

  @override
  Widget build(BuildContext context) {
    final controller = context.read<LedgerUiController>();
    return DecoratedBox(
      key: const Key('transactions-error-state'),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('账单暂时加载失败，请重试。'),
            const SizedBox(height: 8),
            TextButton.icon(
              key: const Key('retry-list-load'),
              onPressed: controller.retryLoadMore,
              icon: const Icon(Icons.refresh),
              label: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }
}

class _LoadMoreFooter extends StatelessWidget {
  const _LoadMoreFooter({required this.controller});

  final LedgerUiController controller;

  @override
  Widget build(BuildContext context) {
    return switch (controller.listStatus) {
      LedgerListStatus.loading => const Center(
        key: Key('load-more-loading'),
        child: Padding(
          padding: EdgeInsets.all(16),
          child: CircularProgressIndicator(),
        ),
      ),
      LedgerListStatus.error => Center(
        child: OutlinedButton.icon(
          key: const Key('load-more-retry'),
          onPressed: controller.retryLoadMore,
          icon: const Icon(Icons.refresh),
          label: const Text('加载失败，重试'),
        ),
      ),
      LedgerListStatus.end => const Center(
        key: Key('load-more-end'),
        child: Padding(padding: EdgeInsets.all(16), child: Text('没有更多账单')),
      ),
      LedgerListStatus.idle =>
        controller.hasMoreEntries
            ? Center(
                child: FilledButton.tonalIcon(
                  key: const Key('load-more-button'),
                  onPressed: controller.loadMore,
                  icon: const Icon(Icons.expand_more),
                  label: const Text('加载更多'),
                ),
              )
            : const SizedBox.shrink(),
    };
  }
}

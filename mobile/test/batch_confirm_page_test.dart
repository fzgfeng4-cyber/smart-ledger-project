import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartledger/domain/parser/multi_transaction_parser.dart';
import 'package:smartledger/shared/clock.dart';
import 'package:smartledger/ui/batch/batch_confirm_page.dart';

void main() {
  final parser = MultiTransactionParser(
    clock: FixedClock(DateTime(2026, 8, 30, 9)),
  );

  testWidgets('批量确认页展示所有候选和逐行编辑控件', (tester) async {
    final result = parser.parse('买菜35元\n加油300元');
    await tester.pumpWidget(
      _TestApp(
        child: BatchConfirmPage(result: result, today: DateTime(2026, 8, 30)),
      ),
    );

    expect(find.byKey(const Key('batch-confirm-page')), findsOneWidget);
    expect(find.byKey(const Key('batch-row-1')), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const Key('batch-row-2')),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.byKey(const Key('batch-row-2')), findsOneWidget);
    expect(find.byKey(const Key('batch-amount-1')), findsOneWidget);
    expect(find.byKey(const Key('batch-category-2')), findsOneWidget);
  });

  testWidgets('错误候选不能提交，移除错误行后可以提交', (tester) async {
    final result = parser.parse('买菜\n加油300元');
    List<Object>? saved;
    await tester.pumpWidget(
      _TestApp(
        child: BatchConfirmPage(
          result: result,
          today: DateTime(2026, 8, 30),
          onConfirm: (transactions) async {
            saved = transactions;
            return true;
          },
        ),
      ),
    );

    final submitButton = tester.widget<FilledButton>(
      find.byKey(const Key('batch-confirm-submit')),
    );
    expect(submitButton.onPressed, isNull);

    await tester.tap(find.byKey(const Key('batch-exclude-1')));
    await tester.pump();
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('batch-confirm-submit')))
          .onPressed,
      isNotNull,
    );
    await tester.tap(find.byKey(const Key('batch-confirm-submit')));
    await tester.pump();
    expect(saved, hasLength(1));
  });

  testWidgets('带提示的候选需要先确认本行', (tester) async {
    final result = parser.parse('35买菜');
    var confirmed = false;
    await tester.pumpWidget(
      _TestApp(
        child: BatchConfirmPage(
          result: result,
          today: DateTime(2026, 8, 30),
          onConfirm: (_) async {
            confirmed = true;
            return true;
          },
        ),
      ),
    );

    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('batch-confirm-submit')))
          .onPressed,
      isNull,
    );
    await tester.scrollUntilVisible(
      find.byKey(const Key('batch-confirm-row-1')),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const Key('batch-confirm-row-1')));
    await tester.pump();
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('batch-confirm-submit')))
          .onPressed,
      isNotNull,
    );
    await tester.tap(find.byKey(const Key('batch-confirm-submit')));
    await tester.pump();
    expect(confirmed, isTrue);
  });

  testWidgets('提交回调抛出普通异常时显示错误并释放提交状态', (tester) async {
    await tester.pumpWidget(
      _TestApp(
        child: BatchConfirmPage(
          result: parser.parse('买菜35元'),
          today: DateTime(2026, 8, 30),
          onConfirm: (_) async {
            throw Exception('测试保存失败');
          },
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('batch-confirm-submit')));
    await tester.pump();

    expect(find.byKey(const Key('batch-submit-error')), findsOneWidget);
    expect(find.text('批量保存失败，请重试。'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('batch-confirm-submit')))
          .onPressed,
      isNotNull,
    );
  });
}

class _TestApp extends StatelessWidget {
  const _TestApp({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(home: child);
  }
}

final class FixedClock implements Clock {
  const FixedClock(this._now);

  final DateTime _now;

  @override
  DateTime now() => _now;
}

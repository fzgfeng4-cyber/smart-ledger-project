import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartledger/domain/models/transaction_type.dart';
import 'package:smartledger/ui/ai/ai_classification_page.dart';

void main() {
  testWidgets('AI 分类页展示建议，未确认前不会进入账目确认', (tester) async {
    var confirmationCount = 0;
    TransactionType? confirmedType;
    String? confirmedCategory;

    await tester.pumpWidget(
      _testApp(
        AiClassificationPage(
          today: DateTime(2026, 8, 31),
          onContinueToConfirmation:
              (input, {required type, required categoryCode}) async {
                confirmationCount += 1;
                confirmedType = type;
                confirmedCategory = categoryCode;
                return true;
              },
        ),
      ),
    );

    await tester.enterText(
      find.byKey(const Key('ai-classification-input')),
      '蜜雪冰城 12',
    );
    await tester.pump();

    expect(find.byKey(const Key('ai-suggestion-panel')), findsOneWidget);
    expect(find.text('餐饮'), findsAtLeastNWidgets(1));
    expect(find.text('支出'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('ai-confirm-button')))
          .onPressed,
      isNull,
    );
    expect(confirmationCount, 0);

    await tester.drag(
      find.byKey(const Key('ai-classification-scroll')),
      const Offset(0, -300),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('ai-confirm-suggestion')));
    await tester.pump();
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('ai-confirm-button')))
          .onPressed,
      isNotNull,
    );

    await tester.tap(find.byKey(const Key('ai-confirm-button')));
    await tester.pumpAndSettle();

    expect(confirmationCount, 1);
    expect(confirmedType, TransactionType.expense);
    expect(confirmedCategory, 'dining');
    expect(find.text('账目已保存。'), findsOneWidget);
  });

  testWidgets('AI 分类页支持切换建议分类，并在离开时保护未保存输入', (tester) async {
    String? confirmedCategory;

    await tester.pumpWidget(
      _testApp(
        AiClassificationPage(
          today: DateTime(2026, 8, 31),
          onContinueToConfirmation:
              (_, {required type, required categoryCode}) async {
                confirmedCategory = categoryCode;
                return true;
              },
        ),
      ),
    );

    await tester.enterText(
      find.byKey(const Key('ai-classification-input')),
      '中国石化300',
    );
    await tester.pump();
    expect(find.text('车辆/加油'), findsAtLeastNWidgets(1));

    await tester.ensureVisible(find.byKey(const Key('ai-category-dining')));
    await tester.tap(find.byKey(const Key('ai-category-dining')));
    await tester.pump();
    expect(
      tester
          .widget<ChoiceChip>(find.byKey(const Key('ai-category-dining')))
          .selected,
      isTrue,
    );
    await tester.ensureVisible(find.byKey(const Key('ai-confirm-suggestion')));
    await tester.tap(find.byKey(const Key('ai-confirm-suggestion')));
    await tester.pump();
    expect(
      tester
          .widget<CheckboxListTile>(
            find.byKey(const Key('ai-confirm-suggestion')),
          )
          .value,
      isTrue,
    );
    await tester.ensureVisible(find.byKey(const Key('ai-confirm-button')));
    await tester.tap(find.byKey(const Key('ai-confirm-button')));
    await tester.pumpAndSettle();
    expect(confirmedCategory, 'dining');

    await tester.enterText(
      find.byKey(const Key('ai-classification-input')),
      '便利店25',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('ai-back')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('ai-discard-dialog')), findsOneWidget);
    expect(find.byKey(const Key('ai-continue-editing')), findsOneWidget);
    expect(find.byKey(const Key('ai-discard-input')), findsOneWidget);
  });
}

Widget _testApp(Widget child) {
  return MaterialApp(theme: ThemeData(useMaterial3: true), home: child);
}

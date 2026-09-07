import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartledger/app/smart_ledger_app.dart';
import 'package:smartledger/domain/ocr/ocr_contract.dart';
import 'package:smartledger/ui/ocr/ocr_capture.dart';
import 'package:smartledger/ui/ocr/ocr_page.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'test_support.dart';

void main() {
  sqfliteFfiInit();

  testWidgets('OCR 页支持选图识别，确认前不会进入账目确认', (tester) async {
    final capture = _FakeOcrCapture(
      OcrResult.success(
        input: OcrInput(
          requestId: 'ocr-test',
          source: const OcrImageSource(type: OcrImageSourceType.gallery),
        ),
        recognizedText: '蜜雪冰城 12',
      ),
    );
    var confirmationCount = 0;
    String? confirmedText;

    await tester.pumpWidget(
      _testApp(
        OcrPage(
          capture: capture,
          today: DateTime(2026, 8, 31),
          onContinueToConfirmation: (text) async {
            confirmationCount += 1;
            confirmedText = text;
            return true;
          },
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('ocr-gallery-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('ocr-result-panel')), findsOneWidget);
    expect(find.text('蜜雪冰城 12'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('ocr-confirm-button')))
          .onPressed,
      isNull,
    );
    expect(confirmationCount, 0);
    expect(capture.lastSource, OcrImageSourceType.gallery);

    await tester.ensureVisible(find.byKey(const Key('ocr-confirm-result')));
    await tester.tap(find.byKey(const Key('ocr-confirm-result')));
    await tester.pump();
    expect(
      tester
          .widget<CheckboxListTile>(find.byKey(const Key('ocr-confirm-result')))
          .value,
      isTrue,
    );
    await tester.ensureVisible(find.byKey(const Key('ocr-confirm-button')));
    await tester.tap(find.byKey(const Key('ocr-confirm-button')));
    await tester.pumpAndSettle();

    expect(confirmationCount, 1);
    expect(confirmedText, '蜜雪冰城 12');
    expect(find.text('账目已保存。'), findsOneWidget);
  });

  testWidgets('OCR 识别失败显示重试，返回时保护识别草稿', (tester) async {
    final capture = _FakeOcrCapture(
      OcrResult.failed(
        input: OcrInput(
          requestId: 'ocr-test',
          source: const OcrImageSource(type: OcrImageSourceType.camera),
        ),
        failureReason: const OcrFailureReason(
          code: OcrFailureCodes.recognitionFailed,
          message: '识别失败，请重试。',
          retryable: true,
        ),
      ),
    );

    await tester.pumpWidget(
      _testApp(
        OcrPage(
          capture: capture,
          today: DateTime(2026, 8, 31),
          onContinueToConfirmation: (_) async => true,
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('ocr-camera-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('ocr-error-state')), findsOneWidget);
    expect(find.text('识别失败，请重试。'), findsOneWidget);
    expect(find.byKey(const Key('ocr-retry-button')), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('ocr-recognized-text')),
      '手动补录 20',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('ocr-back')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('ocr-discard-dialog')), findsOneWidget);
    expect(find.byKey(const Key('ocr-continue-editing')), findsOneWidget);
    expect(find.byKey(const Key('ocr-discard-result')), findsOneWidget);
  });

  testWidgets('相机权限被拒绝时提供系统设置入口', (tester) async {
    final capture = _FakeOcrCapture(
      OcrResult.permissionDenied(
        input: OcrInput(
          requestId: 'ocr-permission-test',
          source: const OcrImageSource(type: OcrImageSourceType.camera),
        ),
      ),
    );

    await tester.pumpWidget(
      _testApp(
        OcrPage(
          capture: capture,
          today: DateTime(2026, 8, 31),
          onContinueToConfirmation: (_) async => true,
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('ocr-camera-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('ocr-open-settings')), findsOneWidget);
    await tester.tap(find.byKey(const Key('ocr-open-settings')));
    await tester.pumpAndSettle();
    expect(capture.openSettingsCalls, 1);
  });

  group('OCR 批量确认接线', () {
    late TestLedgerFixture fixture;

    setUpAll(() async {
      fixture = await TestLedgerFixture.create();
    });

    setUp(() async {
      await fixture.reset();
    });

    tearDownAll(() async {
      await fixture.dispose();
    });

    testWidgets('OCR 多行结果进入 MultiTransactionParser 和批量确认页，确认前不写库', (
      tester,
    ) async {
      final capture = _FakeOcrCapture(
        OcrResult.success(
          input: OcrInput(
            requestId: 'ocr-batch-test',
            source: const OcrImageSource(type: OcrImageSourceType.gallery),
          ),
          recognizedText: '买菜35元\n加油300元',
        ),
      );

      await tester.pumpWidget(
        SmartLedgerApp(controller: fixture.controller, ocrCapture: capture),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('open-accounting-tools')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('accounting-tool-ocr')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('ocr-gallery-button')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('ocr-confirm-result')));
      await tester.tap(find.byKey(const Key('ocr-confirm-result')));
      await tester.pump();
      await tester.ensureVisible(find.byKey(const Key('ocr-confirm-button')));
      await tester.tap(find.byKey(const Key('ocr-confirm-button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byKey(const Key('batch-confirm-page')), findsOneWidget);
      expect(fixture.controller.batchDraft, isNotNull);
      expect(fixture.controller.batchDraft!.transactions, hasLength(2));
      await tester.runAsync(() async {
        expect(await fixture.repository.list(), isEmpty);
      });
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });

    testWidgets('OCR 进入批量确认后返回会丢弃批量草稿且不写库', (tester) async {
      final capture = _FakeOcrCapture(
        OcrResult.success(
          input: OcrInput(
            requestId: 'ocr-batch-back-test',
            source: const OcrImageSource(type: OcrImageSourceType.camera),
          ),
          recognizedText: '买菜35元\n加油300元',
        ),
      );

      await tester.pumpWidget(
        SmartLedgerApp(controller: fixture.controller, ocrCapture: capture),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('open-accounting-tools')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('accounting-tool-ocr')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('ocr-camera-button')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('ocr-confirm-result')));
      await tester.tap(find.byKey(const Key('ocr-confirm-result')));
      await tester.pump();
      await tester.ensureVisible(find.byKey(const Key('ocr-confirm-button')));
      await tester.tap(find.byKey(const Key('ocr-confirm-button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byKey(const Key('batch-confirm-page')), findsOneWidget);
      await tester.tap(find.byKey(const Key('batch-back')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('batch-confirm-page')), findsNothing);
      expect(find.byKey(const Key('ocr-page')), findsOneWidget);
      expect(fixture.controller.batchDraft, isNull);
      await tester.runAsync(() async {
        expect(await fixture.repository.list(), isEmpty);
      });
      expect(find.text('已取消确认，账本未修改。'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });

    testWidgets('OCR provider 返回取消状态时不进入批量确认且不写库', (tester) async {
      final capture = _FakeOcrCapture(
        OcrResult.cancelled(
          input: OcrInput(
            requestId: 'ocr-cancel-test',
            source: const OcrImageSource(type: OcrImageSourceType.camera),
          ),
        ),
      );

      await tester.pumpWidget(
        _testApp(
          OcrPage(
            capture: capture,
            today: DateTime(2026, 8, 31),
            onContinueToConfirmation: (_) async => true,
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('ocr-camera-button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('ocr-result-panel')), findsOneWidget);
      expect(find.byKey(const Key('ocr-confirm-button')), findsOneWidget);
      expect(find.text('已取消识别，账本未修改。'), findsOneWidget);
      expect(find.byKey(const Key('batch-confirm-page')), findsNothing);
    });
  });
}

Widget _testApp(Widget child) {
  return MaterialApp(theme: ThemeData(useMaterial3: true), home: child);
}

final class _FakeOcrCapture implements OcrCaptureService {
  _FakeOcrCapture(this.result);

  final OcrResult result;
  OcrImageSourceType? lastSource;
  int openSettingsCalls = 0;

  @override
  Future<bool> cancel() async => true;

  @override
  Future<bool> openAppSettings() async {
    openSettingsCalls += 1;
    return true;
  }

  @override
  Future<OcrResult> pickAndRecognize({
    required OcrImageSourceType source,
    required String requestId,
  }) async {
    lastSource = source;
    return result;
  }
}

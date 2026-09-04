import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartledger/data/import/import_file_picker.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('MethodChannel 文件选择器读取文件名和字节', () async {
    final channel = const MethodChannel(importFilePickerChannelName);
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'pickCsv');
      return {
        'fileName': '微信账单.csv',
        'bytes': Uint8List.fromList([1, 2, 3]),
      };
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    final picked = await const MethodChannelImportFilePicker().pickCsv();

    expect(picked, isNotNull);
    expect(picked!.fileName, '微信账单.csv');
    expect(picked.bytes, [1, 2, 3]);
  });

  test('MethodChannel 文件选择器取消时返回 null', () async {
    final channel = const MethodChannel(importFilePickerChannelName);
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async => null);
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    expect(await const MethodChannelImportFilePicker().pickCsv(), isNull);
  });
}

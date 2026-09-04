import 'package:flutter/services.dart';

const importFilePickerChannelName = 'smartledger/import_file';

abstract interface class ImportFilePicker {
  Future<PickedImportFile?> pickCsv();
}

final class PickedImportFile {
  PickedImportFile({required this.fileName, required List<int> bytes})
    : bytes = Uint8List.fromList(bytes);

  final String fileName;
  final Uint8List bytes;
}

final class ImportFilePickerException implements Exception {
  const ImportFilePickerException(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() => message;
}

final class MethodChannelImportFilePicker implements ImportFilePicker {
  const MethodChannelImportFilePicker({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(importFilePickerChannelName);

  final MethodChannel _channel;

  @override
  Future<PickedImportFile?> pickCsv() async {
    try {
      final payload = await _channel.invokeMethod<Object?>('pickCsv');
      if (payload == null) {
        return null;
      }
      if (payload is! Map) {
        throw const ImportFilePickerException('文件选择器返回的数据格式无效。');
      }

      final fileName = payload['fileName'];
      if (fileName is! String || fileName.trim().isEmpty) {
        throw const ImportFilePickerException('未读取到所选文件名。');
      }

      return PickedImportFile(
        fileName: fileName,
        bytes: _readBytes(payload['bytes']),
      );
    } on ImportFilePickerException {
      rethrow;
    } on PlatformException catch (error) {
      throw ImportFilePickerException(
        error.message ?? '打开本地文件选择器失败，请重试。',
        cause: error,
      );
    } on MissingPluginException catch (error) {
      throw ImportFilePickerException('当前平台不支持选择本地 CSV 文件。', cause: error);
    } on Object catch (error) {
      throw ImportFilePickerException('读取本地 CSV 文件失败，请重试。', cause: error);
    }
  }

  Uint8List _readBytes(Object? value) {
    if (value is Uint8List) {
      return value;
    }
    if (value is List) {
      final bytes = <int>[];
      for (final item in value) {
        if (item is! int || item < 0 || item > 255) {
          throw const ImportFilePickerException('所选文件的字节数据无效。');
        }
        bytes.add(item);
      }
      return Uint8List.fromList(bytes);
    }
    throw const ImportFilePickerException('未读取到所选文件内容。');
  }
}

enum ImportSourceType {
  unknown('unknown'),
  wechatCsv('wechat_csv'),
  alipayCsv('alipay_csv'),
  otherCsv('other_csv');

  const ImportSourceType(this.code);

  final String code;
}

final class ImportFileSource {
  const ImportFileSource({
    required this.type,
    required this.fileName,
    this.filePath,
    this.charset,
  });

  final ImportSourceType type;
  final String fileName;
  final String? filePath;
  final String? charset;

  Map<String, Object?> toMap() {
    return {
      'type': type.code,
      'file_name': fileName,
      'file_path': filePath,
      'charset': charset,
    };
  }
}

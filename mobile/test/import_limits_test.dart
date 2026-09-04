import 'package:flutter_test/flutter_test.dart';
import 'package:smartledger/domain/import/import_contract.dart';
import 'package:smartledger/domain/import/wechat_csv_parser.dart';

void main() {
  test('超过 CSV 记录数上限时解析器拒绝继续展开输入', () {
    final text = List<String>.generate(
      ImportLimits.maxCsvRecords + 1,
      (index) => '第$index行',
    ).join('\n');

    expect(
      () => const WechatCsvParser().parse(text),
      throwsA(
        isA<ImportInputLimitException>().having(
          (error) => error.message,
          'message',
          'CSV 行数超过 100000 行上限，请拆分账单后重试。',
        ),
      ),
    );
  });
}

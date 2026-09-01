# Smart Ledger Android APP V1 Classification Dart Migration Report

## 1. 本轮状态

`Classification Dart Migration: PASS`

本轮已在真实用户权限环境中完成最终验证：

- `flutter pub get` 正常结束。
- `flutter analyze` 正常结束，结果为 `No issues found! (ran in 8.5s)`。
- `flutter test` 正常结束，32 个测试全部通过。
- `flutter build apk --debug` 正常结束，已重新生成 Debug APK。

验证中曾发现固定支出分类词没有参与收支方向判断，导致 `麦当劳35`、`纸巾30` 被识别为方向未知。本轮已在 `TransactionParser` 内修复：当稳定分类 code 命中支出分类时，也作为支出方向证据；没有分类或方向证据的输入仍不会默认支出。

## 2. 阶段边界

本阶段只迁移 Web Prototype 已冻结的一句话解析和分类规则到 Dart：

- 不修改 `frontend/`。
- 不修改 `backend/`。
- 不写 SQLite schema。
- 不修改 Repository / Data Source。
- 不实现正式 Flutter UI。
- 不进入 App Integration。
- 不加入微信、支付宝、OCR、通知、短信、云同步、登录、多用户或其他 V2/V3 功能。

## 3. 新建和修改文件

新建文件：

- `mobile/lib/domain/parser/parse_result.dart`
- `mobile/lib/domain/parser/classification_service.dart`
- `mobile/lib/domain/parser/transaction_parser.dart`
- `mobile/test/transaction_parser_test.dart`
- `docs/classification-dart-migration.md`

修改文件：

- `PROJECT.md`
- `mobile/lib/domain/parser/transaction_parser.dart`

复用文件：

- `mobile/lib/domain/models/transaction_type.dart`
- `mobile/lib/domain/categories/category_catalog.dart`
- `mobile/lib/shared/clock.dart`

## 4. Parser 架构

Parser 位于 `mobile/lib/domain/parser/`，为纯 Dart 领域逻辑：

- `TransactionParser`：负责一句话解析，输出待确认草稿。
- `ClassificationService`：负责关键词命中、分类候选和分类冲突处理。
- `ParseResult`：负责解析状态、草稿、缺失字段和问题列表。
- `TransactionDraft`：负责承载解析后的待确认字段。

Parser 不导入 `sqflite`、不调用 `TransactionRepository`、不直接保存数据，也不依赖 Flutter Widget。

## 5. TransactionDraft 字段

`TransactionDraft` 继续沿用正式数据契约中的核心字段：

| 字段 | Dart 类型 | 说明 |
| --- | --- | --- |
| `amountCents` | `int?` | 金额，单位为分；缺失或非法时为 `null`。 |
| `type` | `TransactionType?` | `income` / `expense`；无法判断或冲突时为 `null`。 |
| `category` | `String?` | 稳定内部 code；无法确定时为 `null` 或兜底 code。 |
| `note` | `String?` | 去掉金额、日期和句式骨架后的备注。 |
| `originalText` | `String` | 用户最初输入原文，原样保留。 |
| `transactionDate` | `String?` | `YYYY-MM-DD`；非法或不支持日期时为 `null`。 |

`toMap()` 输出继续使用 `amount_cents`、`original_text`、`transaction_date` 等 snake_case 字段名，便于后续 UI / Repository 适配。

## 6. ParseResult 状态

已实现状态：

| 状态 | 含义 |
| --- | --- |
| `ready` | 六个字段已有合法建议，且没有额外歧义。仍然只是待确认草稿。 |
| `needs_confirmation` | 有裸数字、兜底分类、分类冲突等需要用户额外确认的事项。 |
| `needs_input` | 缺金额、多金额、金额非法、方向未知、方向冲突、日期非法、不支持日期或未来日期，保存必须阻塞。 |
| `no_draft` | 空输入或无记账意义输入，不生成草稿。 |

`needsConfirmation` 表示存在额外不确定或阻塞事项。`requiresConfirmation` 表示只要存在草稿就必须经过用户确认，避免后续 UI 把 `ready` 误解为可自动保存。

## 7. 金额规则

已迁移规则：

- 支持整数金额：`5块买菜` -> `500`。
- 支持一位小数：`35.8元吃饭` -> `3580`。
- 支持两位小数：`35.80元吃饭` -> `3580`。
- 支持金额在事项前或事项后：`20打车`、`加油300`。
- 支持裸数字，但增加 `BARE_AMOUNT` 提示。
- 金额核心转换不使用 `double`，使用字符串和 `BigInt` 转换为整数分。
- `0`、负数、小数超过两位、超过 SQLite integer 范围的金额均标记 `INVALID_AMOUNT`。
- 多金额标记 `MULTIPLE_AMOUNTS`，不选第一个、不选最后一个、不求和、不自动拆分。
- 日期片段会先被遮蔽，避免 `2026-08-20` 或 `8月20日` 被误识别为金额。

## 8. 收支方向规则

已迁移规则：

- 收入关键词或收入分类 code 命中后建议 `TransactionType.income`。
- 支出关键词、消费行为词或稳定支出分类 code 命中后建议 `TransactionType.expense`。
- 只有金额时不默认支出，标记 `TYPE_UNKNOWN`。
- 同时出现收入和支出语义时标记 `TYPE_CONFLICT`，`type` 留空，阻塞保存。
- `amount_cents` 始终为正整数分，收入/支出方向只由 `type` 表达。

## 9. 分类规则

分类继续使用 `CategoryCatalog` 的稳定内部 code，没有复制第二套分类主表。

已覆盖分类：

- 支出：`dining`、`groceries_food`、`daily_necessities`、`transportation`、`vehicle_fuel`、`housing`、`communication`、`entertainment`、`children`、`medical`、`other_expense`
- 收入：`salary`、`other_income`

冲突处理：

- `带孩子吃饭86`：核心消费行为为吃饭，建议 `dining`，附加 `CATEGORY_CONFLICT`。
- `给孩子买东西80`：没有具体商品/服务，建议 `children`。
- 支出无法稳定分类时建议 `other_expense`，并附加 `CATEGORY_FALLBACK`。
- 收入非工资时建议 `other_income`，并附加 `CATEGORY_FALLBACK`。
- 多个核心事项或多金额时，不按关键词顺序强行选择分类。

说明：正式文档中的加油分类 code 为 `vehicle_fuel`，不是 `fuel`，本阶段按正式文档使用 `vehicle_fuel`。

## 10. 日期规则

已实现日期表达：

- 未写日期：默认当前本机日期。
- `今天`：当前日期。
- `昨天`：当前日期减 1 天。
- `前天`：当前日期减 2 天。
- `M月D日` / `M月D号`：按当前年份解释。
- `YYYY-MM-DD`。
- `YYYY年M月D日` / `YYYY年M月D号`。

日期会做真实日历校验：

- `2月30日` 标记 `INVALID_DATE`，不默认今天。
- `上周三`、`下个月` 等 V1 不支持表达标记 `UNSUPPORTED_DATE`，不默认今天。
- 未来日期保留候选日期，但标记 `FUTURE_DATE` 并阻塞保存。

## 11. note 与 original_text

实现规则：

- `originalText` 保留用户最初输入原文，包括首尾空格。
- `note` 从解析副本生成，移除金额、日期词、明显句式骨架和常见标点。
- 普通解析不会用清理后的 `note` 覆盖 `originalText`。
- Parser 不保存数据，因此也不会覆盖数据库中已保存交易的 `original_text`。

## 12. 测试覆盖

新增测试文件：

- `mobile/test/transaction_parser_test.dart`

新增 Parser 测试用例数量：

- 18 个 `test()`。

覆盖范围：

- 文档正常案例：买菜、吃面、加油、打车、工资、工资到账、昨天买菜、今天午饭、给孩子买东西、带孩子吃饭、奖金、话费、医院挂号、房租、买衣服、水果、麦当劳。
- 只有金额不猜方向和分类。
- 缺金额阻塞保存。
- 多金额不自动拆分、不选首尾、不求和。
- 一位和两位小数金额精确转分。
- 0、负数、超过两位小数和超大金额非法。
- 空输入和无意义输入不生成草稿。
- 收入关键词和支出关键词分类迁移。
- 孩子场景与核心消费行为冲突。
- 今天、昨天、前天、月日、年月日和 ISO 日期。
- 未来日期、非法日期、不支持日期。
- 收入/支出冲突。
- `original_text` 原样保留。
- Parser 纯 Dart 边界，不导入 SQLite、Repository 或 Database。

测试数据库隔离：

- 本阶段 Parser 测试不使用数据库。
- 既有 SQLite 数据层测试继续使用临时隔离数据库，不触碰用户真实账本。

## 13. 命令验证结果

| 命令 | 结果 | 说明 |
| --- | --- | --- |
| `flutter pub get` | PASS | `Got dependencies!`；6 个 package 有新版但受当前约束限制，不阻塞。 |
| `flutter analyze` | PASS | `No issues found! (ran in 8.5s)`；warning 数量 0。 |
| `flutter test` | PASS | 32 个测试全部通过；`transaction_parser_test.dart` 18 个 Parser 测试全部通过。 |
| `flutter build apk --debug` | PASS | Gradle `assembleDebug` 成功，已重新生成 Debug APK。构建输出有 SDK XML 版本提示，不阻塞本轮构建。 |

Debug APK 实际路径：

- `G:\DevTools\AndroidEnv\workspace\smart-ledger-project\mobile\build\app\outputs\flutter-apk\app-debug.apk`
- 对应原项目路径：`C:\Users\冯志贡\Documents\ChatGPT\记账app\mobile\build\app\outputs\flutter-apk\app-debug.apk`
- 文件大小：153304894 bytes。
- 生成时间：2026/8/31 16:22:21。

## 14. 权限与依赖确认

- 未修改 Android Manifest。
- 未添加相机、相册、通知、短信、通讯录、后台服务、无障碍、外部存储或读取其他 APP 数据权限。
- 未添加网络、AI、OCR、camera、permission_handler、notification、云服务、后台任务或微信/支付宝相关 package。
- 本阶段未修改 `pubspec.yaml`。
- Parser 仍可离线运行。

## 15. 遗留问题

None。

## 16. 是否具备进入下一阶段

代码层面：

- Parser、分类迁移和测试用例已经落盘。
- `flutter pub get`、`flutter analyze`、`flutter test`、`flutter build apk --debug` 已全部通过。

验收层面：

- 强制测试和 APK 构建命令已完成。

结论：

`Ready for Flutter UI / App Integration Next Stage: YES`

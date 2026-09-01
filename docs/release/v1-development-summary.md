# Smart Ledger Android APP V1 开发总结与冻结说明

## 1. 文档用途

本文是 Smart Ledger Android APP V1 的完整开发归档和冻结基线，记录 V1 从产品定义到 Android Release 构建的主要决策、代码结构、测试证据和交付状态。

V1 已冻结。后续开发必须以本文对应的 Git 标签和提交为基线，在新的 V2 分支中进行。除安全修复、构建修复或明确批准的发布修订外，不再直接修改 V1 业务实现。

## 2. 项目基本信息

| 项目 | 内容 |
| --- | --- |
| 项目名称 | Smart Ledger Android APP V1 |
| 产品版本 | `1.0.0` |
| Android `versionCode` | `1` |
| applicationId | `com.fzgfeng4.smartledger` |
| 应用名称 | `Smart Ledger` |
| 技术栈 | Flutter + Dart + SQLite |
| 状态管理 | Provider + ChangeNotifier |
| 数据库版本 | SQLite schema `1` |
| V1 基线标签 | `v1.0.0` |
| V1 最终归档分支建议 | `v1-frozen` |

## 3. 开发原则

- V1 面向个人、单用户、本地使用。
- 核心记账链路不依赖网络、Python、FastAPI 或云端大模型。
- 一句话解析只生成待确认草稿，用户确认后才写入 SQLite。
- 金额以整数分保存，不使用浮点金额作为数据真相。
- 收入和支出由独立的 `type` 字段表达，不使用金额正负表达方向。
- 删除采用软删除，保留原记录并支持撤销恢复。
- 使用最小 Android 权限，不读取其他应用、短信、联系人、相机或定位数据。
- `frontend/` 和 `backend/` 是历史 Web Prototype，Android APP 不依赖它们运行，也不作为 Android V1 的实现目标。

## 4. 完整开发流程

### 4.1 产品和 Web Prototype 基线

项目先完成 Web Prototype，用于验证产品、业务规则、数据模型、分类规则、页面交互、API、测试和 Review。

Web Prototype 技术组成：

- `frontend/`：Vue 3 + TypeScript + Vite。
- `backend/`：Python + FastAPI + SQLite。
- 规则和关键词驱动的一句话解析。
- 固定收入/支出分类。
- 交易 CRUD、统计、软删除、撤销和 SQLite 备份。

Web Prototype 的作用是沉淀 V1 业务规则。Android V1 后续将这些规则迁移到 Dart，并在手机本地完成运行。

### 4.2 Android 阶段初始化

在 `PROJECT.md` 中重新划分 Android APP V1 的边界：

- Android APP 使用 Flutter + Dart。
- 业务逻辑放在 App 内部。
- 数据存储使用本地 SQLite。
- Android 运行时不依赖浏览器、FastAPI、Python 或 localhost。
- 保留 Web Prototype，不修改 `frontend/`、`backend/`。

### 4.3 Mobile Architecture

确定 Flutter 目录和模块边界：

```text
mobile/
├─ lib/
│  ├─ app/
│  ├─ data/
│  │  ├─ backup/
│  │  ├─ repositories/
│  │  └─ sqlite/
│  ├─ domain/
│  │  ├─ categories/
│  │  ├─ models/
│  │  ├─ parser/
│  │  └─ validation/
│  ├─ shared/
│  └─ ui/
│     ├─ editor/
│     ├─ home/
│     ├─ models/
│     ├─ shared/
│     └─ transactions/
├─ test/
└─ android/
```

主要依赖：

- Flutter SDK
- `provider`
- `sqflite`
- `path`
- `sqflite_common_ffi`（测试）

状态管理使用 `LedgerUiController extends ChangeNotifier`，UI 通过 Provider 读取和触发状态变化。

### 4.4 Mobile Data 和 SQLite

V1 只使用一张核心表：

```sql
transactions (
  id INTEGER PRIMARY KEY,
  amount_cents INTEGER NOT NULL,
  type TEXT NOT NULL,
  category TEXT NOT NULL,
  note TEXT,
  original_text TEXT NOT NULL,
  transaction_date TEXT NOT NULL,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  deleted_at TEXT
)
```

数据库配置：

- `DatabaseSchema.version = 1`
- 表名：`transactions`
- 索引：`idx_transactions_date_status`
- 金额约束：`amount_cents > 0`
- 类型约束：`expense` 或 `income`
- 备注最长 200 个字符
- `original_text` 去除首尾空白后必须有内容，最长 500 个字符
- 日期保存为 `YYYY-MM-DD`
- 时间戳保存为 UTC ISO 8601 文本

数据层文件：

| 文件 | 职责 |
| --- | --- |
| `mobile/lib/data/sqlite/app_database.dart` | 打开、关闭 SQLite，使用 schema 版本和 migration |
| `mobile/lib/data/sqlite/database_schema.dart` | SQLite V1 建表、索引和迁移入口 |
| `mobile/lib/data/sqlite/transaction_local_data_source.dart` | SQLite 查询、插入、更新、分页、统计、软删除和恢复 |
| `mobile/lib/data/repositories/transaction_repository.dart` | 领域校验、规范化和数据访问抽象 |
| `mobile/lib/domain/models/ledger_transaction.dart` | 新建、更新和已保存账目模型 |
| `mobile/lib/domain/validation/transaction_validator.dart` | 金额、类型、分类、备注、原文、日期和未来日期校验 |

列表按以下顺序排序：

```text
transaction_date DESC
updated_at DESC
id DESC
```

### 4.5 Classification Dart Migration

Parser 已从 Web Prototype 规则迁移为纯 Dart 领域逻辑：

| 文件 | 职责 |
| --- | --- |
| `mobile/lib/domain/parser/transaction_parser.dart` | 解析金额、日期、方向、分类和备注 |
| `mobile/lib/domain/parser/classification_service.dart` | 关键词、分类候选和冲突选择 |
| `mobile/lib/domain/parser/parse_result.dart` | 解析状态、草稿、问题和缺失字段 |

Parser 不导入 SQLite，不调用 Repository，不直接保存账目，也不依赖 Flutter Widget。

解析状态：

- `ready`：字段已有合法建议，没有额外歧义，但仍必须确认。
- `needs_confirmation`：存在裸金额、兜底分类或分类冲突，需要用户确认。
- `needs_input`：金额、方向、分类、日期等存在阻塞问题，不能保存。
- `no_draft`：空输入或无记账意义文本，不生成草稿。

金额规则：

- `35块买菜` -> `3500` 分。
- `35.8元吃饭` -> `3580` 分。
- `35.80元吃饭` -> `3580` 分。
- 裸数字可以识别，但显示“请核对金额”。
- 0、负数、超过两位小数和超出 SQLite 整数范围的金额拒绝保存。
- 多金额标记 `MULTIPLE_AMOUNTS`，不自动拆分、不求和、不选第一笔或最后一笔。

日期规则：

- 未写日期或写“今天”时使用当前本机日期。
- 支持“昨天”“前天”。
- 支持 `M月D日`、`YYYY年M月D日` 和 `YYYY-MM-DD`。
- 非法日期和暂不支持的日期表达阻止保存。
- 未来日期显示“这个日期在未来，请检查日期。”，修正前不能保存。

分类规则：

| 方向 | 分类 code |
| --- | --- |
| 支出 | `dining`、`groceries_food`、`daily_necessities`、`transportation`、`vehicle_fuel`、`housing`、`communication`、`entertainment`、`children`、`medical`、`other_expense` |
| 收入 | `salary`、`other_income` |

典型样例：

| 输入 | 金额分 | 类型 | 分类 |
| --- | ---: | --- | --- |
| `买菜35` | 3500 | 支出 | `groceries_food` |
| `工资8000` | 800000 | 收入 | `salary` |
| `加油300` | 30000 | 支出 | `vehicle_fuel` |
| `奶粉260` | 26000 | 支出 | 按规则和冲突提示确认分类 |

分类冲突不会被静默掩盖。例如“带孩子吃饭86”会提示餐饮和孩子两个方向，用户需要确认。

### 4.6 Flutter UI

主要页面：

- 首页：Smart Ledger 标题、一句话输入、三个统计数字、最近账单入口。
- 快速记账：输入自然语言，空输入时给出明确提示。
- 确认/编辑页：金额、收入/支出、分类、备注、日期可修改；`original_text` 只读。
- 账单列表：日期倒序、金额、收支、分类、备注、日期、加载更多。
- 编辑账单：保存校验、软删除和二次确认。
- 删除撤销：删除后约 10 秒内可撤销。
- 空状态、加载状态和错误状态。
- 备份入口：导出和恢复本地 JSON 备份。

UI 原则：

- Material 3。
- 中文优先。
- 触控区域和输入框适合 Android 手机。
- 收入/支出不只依赖红绿颜色，同时显示文字和图标。
- 键盘弹出时页面可滚动，不产生布局溢出。
- 不加入预算、账户、资产、复杂图表、登录或多用户入口。

### 4.7 App Integration

启动时真实组装链路：

```text
main.dart
  -> AppDatabase
  -> TransactionLocalDataSource
  -> TransactionRepository
  -> BackupService
  -> TransactionParser
  -> LedgerUiController
  -> SmartLedgerApp
```

完整记账链路：

```text
用户输入
  -> TransactionParser
  -> ClassificationService
  -> ParseResult / EditorDraft
  -> 用户确认或修改
  -> TransactionRepository
  -> TransactionValidator
  -> TransactionLocalDataSource
  -> SQLite
  -> LedgerUiController.refresh
  -> 首页、列表和统计刷新
```

已实现的实时联动：

- 新增收入和支出后列表、最近账单和统计刷新。
- 编辑原账，不新建重复记录。
- 删除设置 `deleted_at`，列表和统计立即排除。
- 撤销恢复同一条记录，列表和统计重新计入。
- 列表分页使用 `limit` 和 `offset`，支持超过 50 条。
- 加载更多支持加载中、无更多、失败和重试状态。
- 未保存草稿离开时提示“继续编辑”或“放弃更改”。

### 4.8 Backup & Restore

Android V1 实际使用 JSON 备份，不使用复杂第三方备份方案。

文件：

```text
mobile/lib/data/backup/backup_service.dart
```

备份根对象包含：

```json
{
  "backup_version": 1,
  "app_version": "1.0.0+1",
  "database_version": 1,
  "created_at": "...",
  "transactions": []
}
```

每笔交易完整保存：

```text
id
amount_cents
type
category
note
original_text
transaction_date
created_at
updated_at
deleted_at
```

备份行为：

- 导出全部交易，包括软删除记录。
- 金额保留 `amount_cents` 整数，不转换为 `double`。
- 使用临时文件写入后重命名，避免产生半写入文件。
- 恢复前校验 JSON、根字段、版本、字段类型、交易 id、时间戳和业务字段。
- 拒绝重复 id、非法金额、非法类型、非法日期和不支持版本。
- 恢复使用 SQLite 事务先替换全部账目，确保数据完整。

自动化测试已验证：

```text
创建 100 条账目
  -> 软删除 10 条
  -> 导出备份
  -> 删除数据库
  -> 重建数据库
  -> 导入恢复
  -> 100 条全部恢复
```

恢复后有效账目数量、软删除状态、总收入、总支出、今日支出、本月收入和本月支出保持一致。

### 4.9 Android Build 和 Release

Android 配置：

- applicationId：`com.fzgfeng4.smartledger`
- `versionName`：`1.0.0`
- `versionCode`：`1`
- minSdk：`24`
- targetSdk：`36`
- 应用名称：`Smart Ledger`
- 图标：mdpi、hdpi、xhdpi、xxhdpi、xxxhdpi 均存在

正式签名配置：

```text
mobile/android/release-keystore/smartledger-release.jks
mobile/android/key.properties
```

签名参数：

- Alias：`smartledger`
- StoreType：`JKS`
- 算法：RSA 2048
- 摘要算法：SHA256withRSA
- 有效期：10000 天
- APK Signature Scheme v2：验证通过

签名密码没有写入 Git 或本文档。`.jks` 和 `key.properties` 已加入 `.gitignore`。

最终产物：

```text
APK:
G:\DevTools\AndroidEnv\workspace\smart-ledger-project\mobile\build\app\outputs\flutter-apk\app-release.apk

AAB:
G:\DevTools\AndroidEnv\workspace\smart-ledger-project\mobile\build\app\outputs\bundle\release\app-release.aab
```

最终签名构建摘要：

| 项目 | 结果 |
| --- | --- |
| APK 大小 | 50,577,900 字节 |
| AAB 大小 | 49,656,589 字节 |
| APK SHA-256 | `0DE4E69F424DEED9B1C1E4EAC54C4A1CBC4E58AC45E1529CA1DFCCD750D925A8` |
| AAB SHA-256 | `6D37EDD529119EE909301D46673732BD7C272668ABE2C694967D837A910569D8` |
| 证书 SHA-256 | `3C:2D:C1:B2:ED:25:86:45:74:FD:B1:25:E7:82:7A:A1:F3:74:CD:A9:D7:88:A0:FD:70:01:DA:5A:01:22:DF:EB` |

权限检查：

- 未声明 `INTERNET`
- 未声明 `CAMERA`
- 未声明 `READ_SMS`
- 未声明 `SEND_SMS`
- 未声明 `READ_CONTACTS`
- 未声明 `RECORD_AUDIO`
- 未声明 `ACCESS_FINE_LOCATION`

APK 中仅发现 AndroidX 自动生成的应用内签名级权限：

```text
com.fzgfeng4.smartledger.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION
```

## 5. 测试和验收结果

### 5.1 Flutter 自动化验证

| 命令 | 结果 |
| --- | --- |
| `flutter pub get` | PASS |
| `flutter analyze` | PASS，0 个问题 |
| `flutter test` | PASS，51/51 |
| `flutter build apk --debug` | PASS |
| `flutter build apk --release` | PASS |
| `flutter build appbundle` | PASS |

测试文件：

- `mobile/test/backup_service_test.dart`
- `mobile/test/final_validation_test.dart`
- `mobile/test/flutter_ui_test.dart`
- `mobile/test/transaction_parser_test.dart`
- `mobile/test/transaction_repository_test.dart`
- `mobile/test/widget_test.dart`

覆盖内容：

- Parser 正常样例和中文输入。
- 金额精度、0、负数、超大金额和小数位校验。
- 收入/支出方向和分类冲突。
- 日期、未来日期、跨月和跨年。
- SQLite 建表、CRUD、分页、统计和持久化。
- 软删除、恢复和约 10 秒撤销状态。
- JSON 备份字段、版本和非法文件校验。
- 100 条账目删除数据库后恢复。
- 首页、输入、确认、编辑、空状态、错误状态和分页 UI。

### 5.2 已完成的浏览器和接口验收

历史 Web Prototype 已完成真实 Frontend -> FastAPI -> SQLite 验收：

- 18 个 V1 验收大项通过。
- 后端自动测试 `24 passed`。
- Vue TypeScript 检查和生产构建通过。
- 桌面和 375px 窄屏 UI 流程通过。

这些结果属于 Web Prototype 的独立验收证据，不改变 Android APP 的本地运行架构。

### 5.3 真机状态

当前环境执行 `adb devices` 没有发现连接设备。因此以下项目尚未完成：

- APK 安装到真实 Android 手机。
- 首次启动和桌面图标验证。
- 真实 Android 中文输入法验证。
- 真实设备上的新增、编辑、删除、撤销、分页和统计冒烟测试。

这是真机环境缺失，不是已确认的业务代码失败。

## 6. V1 冻结范围

V1 已实现并冻结：

- 一句话记账。
- Parser 和 Classification。
- 用户确认和字段修改。
- SQLite 本地持久化。
- 新增、编辑、软删除、撤销恢复。
- 列表、分页和统计。
- JSON 备份和恢复。
- Provider + ChangeNotifier。
- 最小 Android 权限。
- Debug、Release APK 和 AAB 构建链路。

V1 明确不包含：

- OCR。
- AI 自动记账。
- AI 聊天或云端大模型依赖。
- 微信、支付宝、淘宝或银行账单读取/导入。
- 短信、通知、通讯录或其他 App 数据读取。
- 云同步。
- 登录注册。
- 多用户。
- 账户、资产、预算和高级报表。
- 自定义分类。
- 一句话自动拆分多笔账。

## 7. Git 冻结基线

V1 原始归档提交：

```text
e086cd035d576311c7f9c3a33529dc2847ff9228
```

已有标签：

```text
v1.0.0
```

生产签名配置和本总结文档属于 V1 最终交付归档内容，提交到 Git 时应创建新的冻结提交，并建立 `v1.0.0-frozen` 标签，避免移动已经存在的 `v1.0.0` 标签。

建议 V2 开始方式：

```powershell
git switch -c v2-development v1.0.0-frozen
```

V2 代码应优先放入新的目录、模块或明确的 V2 分支。不要直接在 `v1.0.0-frozen` 标签上开发，也不要修改 V1 冻结提交。

## 8. V2 开发前置规则

开始 V2 前先建立：

1. V2 产品需求文档。
2. V2 数据迁移方案。
3. V1 到 V2 的兼容和备份策略。
4. V2 新增权限和隐私边界。
5. V2 测试计划。
6. V2 独立分支。

V2 必须继续保留 V1 的核心不变量，除非经过明确产品和数据迁移决策：

- `amount_cents` 仍然是金额真相。
- `type` 仍然明确区分收入和支出。
- 用户确认前不写入正式账目。
- `original_text` 不被普通编辑覆盖。
- 软删除和备份数据不因新功能静默丢失。
- V1 数据可以被新版本读取或有明确迁移路径。

## 9. 相关文档索引

### 产品和设计

- `PROJECT.md`
- `docs/product-v1.md`
- `docs/technical-research.md`
- `docs/ui-plan.md`

### Android 架构和实现

- `docs/android-v1-plan.md`
- `docs/mobile-architecture.md`
- `docs/mobile-data-model.md`
- `docs/classification-dart-migration.md`
- `docs/android-build-report.md`

### Web Prototype 验收

- `docs/integration-report.md`
- `docs/test-report.md`
- `docs/review-report.md`
- `docs/review-fix-report.md`

### Android Release

- `docs/release/release-package.md`
- `docs/release/uat-checklist.md`
- `docs/release/release-notes-v1.0.0.md`
- `docs/release/final-delivery-report.md`
- `docs/release/production-release-report.md`
- `docs/release/v1-development-summary.md`

## 10. 最终结论

Smart Ledger Android APP V1 的代码、数据层、Parser、Classification、Flutter UI、App Integration、备份恢复、测试和 Release 构建已经形成完整归档。

V1 业务范围冻结，后续不再继续开发 V1 功能。V2 应从 V1 冻结标签创建独立分支，在新的产品、数据和测试决策下继续开发。

当前最终发布条件：

- 自动化和构建：通过。
- 正式签名：通过。
- Git V1 归档：已建立基础标签，最终冻结提交需包含本总结文档。
- 真机 UAT：当前环境未完成。

因此，V1 可以作为 V2 的开发基线，但在真实 Android 设备完成 UAT 前，不应宣称已经完成最终生产上架验收。

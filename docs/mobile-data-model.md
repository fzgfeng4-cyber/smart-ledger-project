# Smart Ledger Android APP V1 Mobile Data Agent 报告

## 1. 阶段结论

本阶段已完成 Android APP V1 的本地数据层最小闭环：

- `LedgerTransaction` Dart 模型。
- 固定 `TransactionType`：`expense` / `income`。
- 固定 V1 分类 code 目录。
- 保存前校验：金额、分类、日期、备注、`original_text`。
- SQLite V1 schema 和基础迁移机制。
- `TransactionLocalDataSource`。
- `TransactionRepository`。
- 新增、读取、编辑、软删除、恢复、分页、最近账目、重复候选查询。
- 今天支出、本月支出、本月收入统计。
- 临时 SQLite 文件隔离测试。
- 关闭并重新打开同一 SQLite 文件后的持久化测试。
- Debug APK 回归构建。

本阶段未实现：

- 一句话 Parser。
- Classification Dart 迁移。
- 正式 Flutter UI。
- APP 集成流程。
- 正式备份业务。
- 微信、支付宝、OCR、通知、云同步、登录等 V2/V3 功能。

## 2. 架构边界确认

Android APP V1 继续使用：

```text
Flutter / Dart
  -> Repository
  -> Data Source
  -> 手机本地 SQLite
```

本阶段没有引入 FastAPI、Python、localhost、浏览器或外部 Backend 运行依赖。`frontend/` 和 `backend/` 未修改，仍然只作为 Web Prototype 参考。

## 3. 数据模型

正式账目模型继续沿用 Web Prototype 已冻结的十字段：

| 字段 | Dart 字段 | SQLite 列 | 规则 |
| --- | --- | --- | --- |
| `id` | `id` | `id` | SQLite 生成的整数主键。 |
| `amount_cents` | `amountCents` | `amount_cents` | 正整数分，不能为 0 或负数。 |
| `type` | `type` | `type` | 只能是 `expense` / `income`。 |
| `category` | `category` | `category` | 稳定内部 code。 |
| `note` | `note` | `note` | 可空，trim 后空值保存为 `NULL`，最长 200。 |
| `original_text` | `originalText` | `original_text` | 原始输入原样保留，最长 500，普通编辑不改。 |
| `transaction_date` | `transactionDate` | `transaction_date` | `YYYY-MM-DD`，有效日期，不能未来。 |
| `created_at` | `createdAt` | `created_at` | UTC ISO 8601。 |
| `updated_at` | `updatedAt` | `updated_at` | UTC ISO 8601。 |
| `deleted_at` | `deletedAt` | `deleted_at` | `NULL` 表示有效，非空表示软删除。 |

金额继续只用整数分计算，不使用 `double` 或负数表达收支方向。

## 4. SQLite schema

当前数据库文件名：

```text
smart-ledger.sqlite
```

SQLite V1 schema：

```sql
CREATE TABLE transactions (
  id INTEGER PRIMARY KEY,
  amount_cents INTEGER NOT NULL CHECK (amount_cents > 0),
  type TEXT NOT NULL CHECK (type IN ('expense', 'income')),
  category TEXT NOT NULL,
  note TEXT CHECK (note IS NULL OR length(note) <= 200),
  original_text TEXT NOT NULL
    CHECK (length(trim(original_text)) >= 1 AND length(original_text) <= 500),
  transaction_date TEXT NOT NULL,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  deleted_at TEXT
);

CREATE INDEX idx_transactions_date_status
ON transactions (transaction_date, deleted_at);
```

迁移机制：

- 当前 `DatabaseSchema.version = 1`。
- `onCreate` 从版本 0 执行到当前版本。
- `onUpgrade` 按版本逐步执行迁移。
- 不支持数据库降级，降级会明确抛错，避免静默破坏本地账目。
- 不新增第二张核心表。

## 5. 分类 code

本阶段已将固定分类 code 放入唯一目录：

```text
mobile/lib/domain/categories/category_catalog.dart
```

支出分类：

```text
dining
groceries_food
daily_necessities
transportation
vehicle_fuel
housing
communication
entertainment
children
medical
other_expense
```

收入分类：

```text
salary
other_income
```

保存前校验会拒绝未知 code，也会拒绝 `income` 使用支出分类、`expense` 使用收入分类。

## 6. Repository 能力

当前 Repository 文件：

```text
mobile/lib/data/repositories/transaction_repository.dart
```

已提供能力：

- `create`
- `findById`
- `update`
- `softDelete`
- `restore`
- `list`
- `recent`
- `findLatestDuplicateCandidate`
- `todayExpenseCents`
- `monthExpenseCents`
- `monthIncomeCents`

约束：

- UI 后续不得直接写 SQL。
- SQL 集中在 `mobile/lib/data/sqlite/transaction_local_data_source.dart`。
- 普通列表、读取、统计只返回或计算 `deleted_at IS NULL` 的有效记录。
- 编辑保持 `id`、`created_at`、`original_text` 不变。
- 软删除和恢复都更新 `updated_at`。

## 7. 依赖调整

当前运行依赖：

| 依赖 | 当前用途 |
| --- | --- |
| `provider` | 后续 Provider + ChangeNotifier 状态管理。 |
| `sqflite` | Android 手机本地 SQLite。 |
| `path` | 数据库路径拼接。 |

当前测试依赖：

| 依赖 | 当前用途 |
| --- | --- |
| `sqflite_common_ffi` 2.3.6 | 在 Windows 测试中创建临时 SQLite 文件。 |
| `sqlite3` 2.7.6 override | 避免测试用 `sqlite3 3.x` native assets 污染 Android APK 构建。 |

`path_provider` 本阶段已移除。原因：

- 当前数据层实际使用 `sqflite.getDatabasesPath()` 获取数据库目录，不需要 `path_provider`。
- `path_provider_android 2.3.1` 会引入 `jni` native 子工程。
- 本轮首次 Debug APK 构建因此在 `:jni:buildCMakeDebug[arm64-v8a]` 失败，错误为 `MalformedJsonException: Invalid escape sequence`。
- 移除当前未使用的 `path_provider` 后，依赖树不再包含 `jni`，Debug APK 构建通过。

后续备份阶段如果确实需要临时目录或系统文件保存能力，应由 Backup/Android Build 阶段重新选择依赖，并再次实测 APK 构建和权限清单。

## 8. 权限复核

本阶段没有修改 Android Manifest，也没有新增 Android 权限。

源码 Manifest 检查结果：

- 未发现 `uses-permission`。
- 未发现 `INTERNET`。
- 未发现相机、通知、短信、通讯录、前台服务、外部存储相关权限。

APK 产物复核：

```text
package: com.fzgfeng4.smartledger
permission: com.fzgfeng4.smartledger.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION
uses-permission: name='com.fzgfeng4.smartledger.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION'
```

该权限是构建链生成的应用私有动态广播权限，不是相机、通知、短信、通讯录、外部存储、网络或读取其他 APP 数据权限。

## 9. 验证结果

执行目录：

```text
G:\DevTools\AndroidEnv\workspace\smart-ledger-project\mobile
```

验证命令和结果：

| 命令 | 结果 |
| --- | --- |
| `flutter pub get` | PASS |
| `flutter analyze` | PASS，No issues found |
| `flutter test` | PASS，13 tests passed |
| `flutter build apk --debug` | PASS |

Debug APK 实际路径：

```text
C:\Users\冯志贡\Documents\ChatGPT\记账app\mobile\build\app\outputs\flutter-apk\app-debug.apk
```

APK 大小：

```text
153304894 bytes
```

生成时间：

```text
2026-08-31 11:45:34
```

说明：这是包含当前数据层代码的 Debug APK 回归产物，不是最终 Android APP V1 交付 APK。

## 10. 测试覆盖

已新增测试文件：

```text
mobile/test/transaction_repository_test.dart
```

覆盖内容：

- schema 字段和索引。
- 13 个固定分类 code。
- 新增账目、整数分、备注归一、`original_text` 保留。
- 非法金额、分类不匹配、未知分类、未来日期、空原始输入拒绝。
- 编辑不改 `id`、`created_at`、`original_text`。
- 软删除隐藏有效列表，恢复保留同一行。
- `limit/offset` 分页和排序。
- 55 条账目三页连续读取，确认超过 50 条后继续分页不重复、不漏项。
- 今天支出、本月支出、本月收入统计。
- 统计排除软删除记录。
- 关闭并重新打开同一 SQLite 文件后数据仍存在。
- 重复账允许保存，并能查询最近重复候选。
- 已删除账目恢复前不能编辑。

## 11. 当前状态

Mobile Data Agent 结论：

```text
Mobile Data: PASS
Ready for Classification Dart Migration: YES
```

下一步应进入：

```text
Classification Dart Migration Agent
```

下一阶段只应迁移一句话解析与分类规则到 Dart，不应反向修改本阶段已经稳定的数据模型、SQLite schema、Repository 边界或 Web Prototype。

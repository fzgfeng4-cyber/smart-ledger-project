# Smart Ledger Android APP V1 阶段总说明

## 1. 文档定位

本文是 Smart Ledger Android APP V1 的阶段总说明。它不替代既有产品、数据、分类、UI、API、测试和 Review 文档，而是说明 Android 阶段如何复用 Web Prototype 的已验证成果，并重新建立移动端代码边界。

本文最初用于 Android 阶段规划和边界初始化。当前 Android APP V1 已完成代码开发、自动化验证和 Release 构建，并已进入 V1 冻结归档；文中早期“尚未创建 mobile/”等表述属于启动阶段记录，当前状态以 `PROJECT.md` 和 `docs/release/` 下的最终归档文档为准。

## 2. Web Prototype 正式状态

Smart Ledger Web Prototype 已完成产品和业务逻辑验证。

它包含：

- Vue 3 + TypeScript + Vite 前端。
- Python + FastAPI 后端。
- SQLite 数据库。
- 一句话解析。
- 固定分类。
- 账目 CRUD。
- 首页统计。
- SQLite 备份。
- Test 和 Review。

`frontend/` 和 `backend/` 继续保留为 Web Prototype。Android APP V1 不依赖它们运行，不要求用户启动浏览器、Python、FastAPI 或 localhost。

## 3. Android APP V1 最终架构

Android APP V1 正式采用：

```text
Flutter
+ Dart
+ APP 内部业务逻辑
+ 手机本地 SQLite
+ Android APK
```

运行时目标：

- 安装 APK 后手机桌面出现 Smart Ledger 图标。
- 点击图标直接打开 APP。
- 可以离线记账。
- 数据保存在手机本地 SQLite。
- APP 关闭后重新打开，数据仍然存在。

Android APP V1 不采用 `Flutter -> FastAPI -> SQLite` 作为运行架构。FastAPI 只作为 Web Prototype 和未来 API/云同步参考。

## 4. Android APP V1 产品范围

Android APP V1 继续复用已验证的核心需求：

- 一句话记账。
- 自动识别金额、收入/支出、分类、备注和日期。
- 不确定结果不能乱猜。
- 用户确认后保存。
- 用户可修改识别结果。
- 手机本地 SQLite 持久化。
- 账单列表。
- 加载更多/分页。
- 编辑。
- 软删除。
- 撤销删除。
- 今天支出。
- 本月支出。
- 本月收入。
- `original_text` 保留。
- 本地数据备份。
- APP 关闭后重新打开，数据仍然存在。

## 5. Android APP V1 不做项

当前 Android V1 不做：

- 微信自动读取。
- 支付宝自动读取。
- 淘宝同步。
- OCR。
- 通知读取。
- 短信读取。
- 云同步。
- 登录注册。
- 多用户。
- 复杂预算。
- 高级图表。
- 强制依赖云端大模型。

不得因为目标平台改成 Android，就提前申请权限或实现未来版本能力。

## 6. 数据和规则复用

Android APP V1 必须复用以下 Web Prototype 基线：

- Transaction 十字段：`id`、`amount_cents`、`type`、`category`、`note`、`original_text`、`transaction_date`、`created_at`、`updated_at`、`deleted_at`。
- 金额用整数分保存。
- `type` 只允许 `income` 和 `expense`。
- 分类使用固定稳定 code。
- `original_text` 保存用户最初输入。
- 删除使用 `deleted_at` 软删除。
- 统计只统计未删除记录。
- 解析结果必须进入确认流程，不能直接保存。

Android 阶段不得另造第二套字段、分类、金额语义、日期语义或删除语义。

## 7. 代码边界

正式边界：

```text
frontend/  Web Prototype，Android 阶段不修改
backend/   Web Prototype，Android 阶段不作为运行依赖
mobile/    Flutter Android APP，后续 Android V1 唯一主要代码目录
```

Android 阶段初始化时只确认代码边界；当前 `mobile/` 已作为 Android APP V1 唯一主要代码目录完成实现。后续 V2 必须使用独立分支或明确的 V2 模块，不得覆盖 Web Prototype。

## 8. 权限原则

Android APP V1 遵守最小权限原则。

当前不要申请：

- 相机。
- 相册。
- 通知。
- 短信。
- 通讯录。
- 后台服务。
- 无障碍。
- 读取其他 APP 数据。

SQLite 数据库优先放在 APP 私有目录，不为数据库申请额外外部存储权限。备份功能后续优先使用 Android 正常系统文件选择/保存机制。

## 9. Agent 保留决策

Android 阶段保留这些 Agent：

| Agent | 职责 |
| --- | --- |
| 主 Agent | 阶段控制、调度、集成和最终验收。 |
| Mobile Architecture Agent | Flutter 架构、依赖、目录和模块边界。 |
| Mobile Data Agent | SQLite、repository、持久化、分页、统计、软删除和备份。 |
| Classification Migration Agent | 将已验证解析规则迁移到 Dart。 |
| Flutter UI Agent | 手机页面和交互状态。 |
| Android Build Agent | Android Manifest、图标、权限、签名和 APK 构建。 |
| Mobile Test Agent | Dart、Widget、SQLite、集成和安装验收测试。 |
| Mobile Review Agent | 最终独立审查。 |

不单独设 SQLite Implementation Agent 和 App Integration Agent。SQLite 实现归 Mobile Data Agent，集成归主 Agent。

## 10. Skill 保留决策

后续保留这些 Android 专用 Skill：

- `skills/mobile-architecture.md`
- `skills/mobile-data.md`
- `skills/classification-migration.md`
- `skills/flutter-ui.md`
- `skills/android-build.md`
- `skills/mobile-testing.md`
- `skills/mobile-review.md`

旧的 `skills/frontend.md` 和 `skills/backend.md` 只适用于 Web Prototype，不适用于 Android APP V1。

## 11. Android APP 开发顺序

1. Android 阶段初始化。
2. Mobile Architecture。
3. Mobile Data Model。
4. Classification Dart Migration。
5. Flutter UI。
6. SQLite Implementation。
7. App Integration。
8. Android Build。
9. Mobile Test。
10. Mobile Review。
11. APK Delivery。
12. Android APP V1 Complete。

每一步完成后必须记录状态和证据。未经用户确认，不自动进入下一步。

## 12. 当前归档状态和后续方向

Android APP V1 已完成：

- Flutter + Dart 应用代码。
- 本地 SQLite 数据层、Repository、分页、统计、软删除和恢复。
- 纯 Dart Parser / Classification。
- Flutter UI 和 App Integration。
- JSON 备份恢复。
- `flutter analyze`、`flutter test`、Debug/Release APK 和 AAB 验证。
- Release 签名、包名、权限和构建产物归档。

当前仍待完成：

- 目标 Android 真机安装和启动验证。
- 真机中文输入法、离线记账、关闭重开、备份恢复和完整操作链路 UAT。

下一步不是继续拆分 V1 Agent，而是：

1. 按 `docs/release/uat-checklist.md` 完成真机 UAT。
2. 以 `v1.0.0-frozen` 为基线创建 V2 独立分支。
3. 先建立 V2 产品需求、数据迁移、权限隐私和测试计划，再实现 V2 功能。

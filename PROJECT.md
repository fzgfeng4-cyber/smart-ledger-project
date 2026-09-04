# Smart Ledger 项目总览

## 1. 项目名称

Smart Ledger / 智能记账

## 2. 项目定位

Smart Ledger 是一个个人长期自用的智能记账项目。项目已经完成一个 Web 版本原型，用来验证产品需求、业务规则、数据模型、分类规则、UX/UI、API、前后端联调、测试和 Review。当前正式进入 Android APP V1 阶段，目标是生成可以安装到 Android 手机上的 APK。

本项目继续采用分阶段、多 Agent 的工作方式。每个阶段都必须先明确范围、文件边界、接口契约和验收标准，再进入实现。

## 3. 当前阶段总览

项目现在明确分为两个阶段，不再把 Web Prototype 当作 Android APP 的运行依赖。

| 阶段 | 状态 | 说明 |
| --- | --- | --- |
| Smart Ledger Web Prototype | 已完成产品和业务逻辑验证 | 已完成 Vue 3 + TypeScript + Vite、FastAPI、SQLite、一句话解析、分类、CRUD、统计、备份、Test 和 Review。 |
| Smart Ledger Android APP V1 | V1 开发完成 / 冻结归档，真机 UAT 待完成 | `mobile/` 已完成 Flutter UI、App Integration、本地 SQLite、Parser、Classification、备份恢复、自动化测试和 Release APK/AAB 构建；当前仅剩目标 Android 真机安装及设备级 UAT。 |

Web Prototype 的 `frontend/` 和 `backend/` 必须继续保留。不得删除、覆盖或重构它们，也不得让 Android APP 运行时依赖浏览器、Python、FastAPI 或 localhost。

## 4. Smart Ledger Web Prototype

### 4.1 正式状态

Web Prototype 已完成产品和业务逻辑验证。它的价值是证明 Smart Ledger V1 的核心闭环可行，并沉淀可复用的需求、数据模型、分类规则、交互设计、API 契约、测试案例和 Review 结论。

### 4.2 技术组成

Web Prototype 包含：

- `frontend/`：Vue 3 + TypeScript + Vite。
- `backend/`：Python + FastAPI + SQLite。
- 一句话解析：规则 + 关键词 + 正则表达式。
- 固定分类体系。
- Transaction CRUD。
- 首页统计。
- SQLite 备份。
- Test 和 Review 报告。

### 4.3 后续边界

- `frontend/` 和 `backend/` 继续作为 Web Prototype 保留。
- Android APP Agent 不修改旧 Web 业务代码。
- FastAPI 后端可作为未来 API、云同步或规则参考，但不是 Android APP V1 的运行依赖。
- Web Prototype 的完成状态不能被误写成 Android APP 已完成。

## 5. Smart Ledger Android APP V1

### 5.1 当前状态

Android APP V1 的代码开发和自动化验收已完成，当前进入：

`V1 冻结归档 / 准备进入 V2 规划`

当前已完成项目状态切换、移动端架构、Android 开发环境恢复、Flutter Android 工程、本地 SQLite 数据层、Dart Parser / Classification、正式 Flutter UI、App Integration、JSON 备份恢复、自动化测试和 Release 构建。`mobile/` 是 Android APP V1 的唯一主要代码目录，`frontend/` 和 `backend/` 仍是独立保留的 Web Prototype。

当前已具备：

- `flutter pub get`、`flutter analyze`、`flutter test` 通过，自动化测试 `51/51`。
- Debug APK、Release APK 和 AAB 已生成。
- Release APK/AAB 已使用本地 release keystore 签名并完成签名校验。
- V1 代码和文档已建立 `v1.0.0-frozen` 归档标签。

当前仍待完成：

- 目标 Android 真机安装和首次启动 UAT。
- 真机中文输入法、关闭重开、备份恢复及完整操作链路验收。

因此，V1 已完成开发并可作为 V2 基线，但在真机 UAT 完成前不宣称“最终生产上架验收完成”。

### 5.2 最终目标

Android APP V1 必须达到：

1. 生成 Android APK。
2. APK 可以安装到 Android 手机。
3. 手机桌面出现 Smart Ledger 图标。
4. 点击图标直接打开 APP。
5. 不依赖浏览器。
6. 不依赖 Python。
7. 不依赖 FastAPI。
8. 不依赖 localhost。
9. 可以离线记账。
10. 数据保存在手机本地 SQLite。
11. APP 关闭后重新打开，数据仍然存在。

### 5.3 Android APP V1 技术架构

Android APP V1 正式采用：

| 项目 | 决策 |
| --- | --- |
| 应用形态 | Android 原生安装包 APK |
| 技术栈 | Flutter + Dart |
| 业务逻辑 | APP 内部实现，不依赖外部后端服务 |
| 数据库 | 手机本地 SQLite |
| 一句话解析 | Dart 内规则 + 关键词 + 正则表达式 |
| AI | 不强制依赖云端大模型，不要求 API Key，不依赖网络完成核心记账 |
| 运行方式 | 用户点击手机桌面图标直接打开 |

Android APP V1 不采用 `Flutter -> FastAPI -> SQLite` 这种运行时依赖额外后端服务的结构。

## 6. Android APP V1 产品范围

Android APP V1 继续沿用 Web Prototype 已验证的核心需求。

V1 必须包含：

- 一句话记账。
- 自动识别金额、收入/支出、分类、备注和日期。
- 不确定结果不能乱猜。
- 用户确认后保存。
- 用户可修改识别结果。
- 手机本地 SQLite 持久化。
- 账单列表。
- 加载更多/分页。
- 编辑账目。
- 软删除。
- 撤销删除。
- 今天支出。
- 本月支出。
- 本月收入。
- `original_text` 原始输入保留。
- 本地数据备份。
- APP 关闭后重新打开，数据仍然存在。

识别结果永远只是待确认建议。用户没有确认前，不能写入 SQLite，不能进入列表，也不能计入统计。

## 7. Android APP V1 数据和规则基线

Android APP V1 复用 Web Prototype 已冻结的业务模型。

Transaction 字段保持：

- `id`
- `amount_cents`
- `type`
- `category`
- `note`
- `original_text`
- `transaction_date`
- `created_at`
- `updated_at`
- `deleted_at`

金额继续使用整数分保存，例如：

- 35 元保存为 `3500`
- 35.80 元保存为 `3580`
- 300 元保存为 `30000`

收入/支出继续只允许：

- `income`
- `expense`

分类继续使用稳定内部 code：

| type | code | 中文名称 |
| --- | --- | --- |
| expense | dining | 餐饮 |
| expense | groceries_food | 买菜/食品 |
| expense | daily_necessities | 日用品 |
| expense | transportation | 交通 |
| expense | vehicle_fuel | 车辆/加油 |
| expense | housing | 居住 |
| expense | communication | 通讯 |
| expense | entertainment | 娱乐 |
| expense | children | 孩子 |
| expense | medical | 医疗 |
| expense | other_expense | 其他支出 |
| income | salary | 工资 |
| income | other_income | 其他收入 |

Android APP V1 不因为改用 Flutter 而重新发明字段、分类、金额规则、日期规则、软删除规则或确认流程。

## 8. Android APP V1 明确不做

以下能力全部不属于当前 Android APP V1。任何 Agent 不得因为改成手机 APP 而提前加入：

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
- 相机识别。
- 相册识别。
- 读取其他 APP 数据。
- 后台自动采集。
- 无障碍采集。
- 一句话自动拆分多笔账。
- 自定义分类。
- 独立商户字段。
- 独立支付来源字段。

未来如果要研究 V2/V3/V4，必须先重新做产品、权限、数据、法律合规和用户授权设计，不能在 Android V1 中暗中预埋。

## 9. 代码目录边界

当前正式代码边界如下：

```text
Smart Ledger/
├─ PROJECT.md
├─ docs/
├─ skills/
├─ frontend/
│  └─ Web Prototype
├─ backend/
│  └─ Web Prototype
└─ mobile/
   └─ Flutter Android APP
```

目录职责：

| 目录 | 状态 | 职责 |
| --- | --- | --- |
| `frontend/` | 已存在 | Web Prototype 前端。Android 阶段不得修改。 |
| `backend/` | 已存在 | Web Prototype 后端和 SQLite 参考实现。Android 阶段不得作为运行依赖。 |
| `mobile/` | 已完成 V1 实现 | Android APP V1 唯一主要代码目录，包含 Flutter UI、Parser、SQLite、Repository、备份、测试和 Android 构建配置。 |
| `docs/` | 已存在 | 项目文档、阶段设计和验收报告。 |
| `skills/` | 已存在 | 分阶段 Agent 工作规则，包含 Android 阶段移动端专用 Skill。 |

Android 阶段初始化时只确认结构；当前 `mobile/` 已完成 V1 实现，后续 V2 必须基于冻结标签或独立分支继续。

## 10. Android 权限原则

Android APP V1 是手动一句话记账应用，遵守最小权限原则。

当前阶段不要申请：

- 相机权限。
- 相册或媒体读取权限。
- 通知权限。
- 短信权限。
- 通讯录权限。
- 后台服务权限。
- 无障碍权限。
- 读取其他 APP 数据的权限。

如果 SQLite 使用 APP 私有目录，不应为数据库申请额外外部存储权限。

本地数据备份后续优先使用 Android 正常系统文件选择/保存机制，不通过宽泛存储权限绕开平台规则。

## 11. Android APP V1 阶段进度

以下状态已根据当前 `mobile/` 实际代码、自动化测试、Release 构建和归档文档同步。历史阶段报告保留各阶段当时的验收口径，不代表当前状态。

| 阶段 | 状态 | 说明 |
| --- | --- | --- |
| 第 0 步：Android 阶段初始化 | 已完成 | 已更新项目状态、冻结 Android 边界、建立阶段计划。 |
| Mobile Architecture | 已完成 | 已在 `docs/mobile-architecture.md` 确定 Flutter 项目结构、依赖、状态管理、模块边界和代码规范。 |
| Mobile Data Model | 已完成 | 已写入 `docs/mobile-data-model.md`；Transaction、分类、日期、软删除、Repository 和 SQLite schema 已落到 Flutter 数据层。 |
| Classification Dart Migration | 已完成 | `mobile/lib/domain/parser/` 已实现纯 Dart Parser、分类服务和 ParseResult，`docs/classification-dart-migration.md` 已记录报告；`flutter pub get`、`flutter analyze`、`flutter test`、`flutter build apk --debug` 已全部通过。 |
| Flutter UI | 已完成 | 已实现首页、快速记账、确认/修改、账单列表、编辑、统计、撤销、加载/空/错误状态和草稿防丢失。 |
| SQLite Implementation | 已完成 | 已实现 SQLite 初始化、V1 migration、CRUD、分页、统计、软删除、恢复、持久化以及 JSON 备份恢复。 |
| App Integration | 已完成 | Parser、确认表单、Repository、SQLite、统计、删除撤销、备份恢复和 UI 已串联。 |
| Android Build | 已完成 | Flutter、Android SDK、JDK、Gradle、Manifest、权限、applicationId、namespace 和 Release 签名构建均已核验。 |
| Mobile Test | 已完成（自动化） | `flutter analyze` 通过，`flutter test` 为 `51/51`；真机 UAT 尚未执行。 |
| Mobile Review | 已完成（冻结归档审查） | V1 范围、代码边界、权限、数据、测试、构建和发布文档已完成归档审查。 |
| APK Delivery | 已完成（候选包） | Release APK 和 AAB 已生成、签名校验通过并保留实际路径；目标 Android 真机安装待执行。 |
| Android APP V1 Complete | 已完成开发 / 真机 UAT 待完成 | V1 代码和自动化验收完成；最终设备级完成标记须等真机安装、打开、离线记账、重启持久化和备份验收。 |

## 12. Android 阶段 Agent 分工

Android 阶段保留必要角色，不为了多 Agent 增加无意义文件。

| Agent | 是否保留 | 主要职责 | 文件边界 |
| --- | --- | --- | --- |
| 主 Agent | 保留 | 范围控制、阶段切换、Agent 调度、最终整合和验收 | `PROJECT.md`、阶段总文档、最终报告 |
| Mobile Architecture Agent | 保留 | Flutter 架构、目录、依赖、状态管理、模块边界、Android 工程基线 | `docs/mobile-architecture.md`，后续 `mobile/` 架构骨架 |
| Mobile Data Agent | 保留 | 手机 SQLite schema、DAO/repository、迁移、备份和持久化口径 | `docs/mobile-data-model.md`，后续 `mobile/lib/.../data/` |
| Classification Migration Agent | 保留 | 将现有分类和解析规则迁移为 Dart，并保证行为与文档一致 | `docs/classification-dart-migration.md`，后续 `mobile/lib/.../domain/` |
| Flutter UI Agent | 保留 | 手机页面和交互状态实现 | `docs/mobile-ui-plan.md`，后续 `mobile/lib/.../ui/` |
| Android Build Agent | 保留 | Android Manifest、图标、权限检查、签名、APK 构建 | `docs/android-build-report.md`，后续 `mobile/android/` |
| Mobile Test Agent | 保留 | Dart、Widget、SQLite、集成和真机/APK验收测试 | `docs/mobile-test-report.md`，后续 `mobile/test/`、`mobile/integration_test/` |
| Mobile Review Agent | 保留 | 最终独立审查，不直接扩展功能 | `docs/mobile-review-report.md` |

合并原则：

- Mobile Architecture 和 Mobile Data 可以先后执行，但不建议合并成一个长期 Agent，因为架构边界和 SQLite 正确性都很关键。
- SQLite Implementation 不单独设为 Agent，归入 Mobile Data Agent 的实现阶段。
- App Integration 不单独设为 Agent，归主 Agent 协调。
- 不新增独立 Product Agent；Android V1 复用已经冻结的产品需求，只在移动端差异处补充。

## 13. Android 阶段文档计划

保留以下 Android 阶段文档：

| 文档 | 是否保留 | 用途 |
| --- | --- | --- |
| `docs/android-v1-plan.md` | 保留 | Android 阶段总说明、范围、架构、Agent 分工和开发顺序。 |
| `docs/mobile-architecture.md` | 保留 | Flutter APP 架构和依赖决策。 |
| `docs/mobile-data-model.md` | 保留 | 手机本地 SQLite 数据模型、迁移、备份和持久化规则。 |
| `docs/classification-dart-migration.md` | 保留 | Dart 解析规则迁移设计和案例对照。 |
| `docs/mobile-ui-plan.md` | 保留 | 手机端 UI/UX 落地方案。 |
| `docs/android-build-report.md` | 保留 | APK 构建、Manifest、图标、权限和签名记录。 |
| `docs/mobile-test-report.md` | 保留 | 移动端测试和真机/安装验收记录。 |
| `docs/mobile-review-report.md` | 保留 | Android APP V1 最终独立 Review。 |

不单独新增 `docs/mobile-api-contract.md`。Android V1 没有 FastAPI 运行时 API，应使用 Dart service/repository 内部接口，由 `mobile-architecture` 和 `mobile-data-model` 文档共同约束。

## 14. Android 阶段 Skill 计划

保留以下移动端专用 Skill：

| Skill | 是否保留 | 理由 |
| --- | --- | --- |
| `skills/mobile-architecture.md` | 保留 | 控制 Flutter 架构、依赖和代码边界。 |
| `skills/mobile-data.md` | 保留 | 控制 SQLite、持久化、备份和数据正确性。 |
| `skills/classification-migration.md` | 保留 | 控制解析规则从 Web/Python 到 Dart 的一致性。 |
| `skills/flutter-ui.md` | 保留 | 控制手机 UI、交互和不确定状态呈现。 |
| `skills/android-build.md` | 保留 | 控制 Manifest、权限、图标、签名和 APK 构建。 |
| `skills/mobile-testing.md` | 保留 | 控制移动端测试范围和证据记录。 |
| `skills/mobile-review.md` | 保留 | 控制最终审查范围和问题分级。 |

不新增独立 `sqlite-implementation.md` 或 `app-integration.md` Skill。SQLite 实现归 `mobile-data`，集成归主 Agent 统筹，避免角色过碎。

## 15. Android APP 开发完整顺序

1. 第 0 步：Android 阶段初始化，更新 `PROJECT.md`，创建 Android 阶段总说明。
2. Mobile Architecture Agent：冻结 Flutter 技术结构、依赖选择、目录结构、状态管理、模块边界和 Android 工程基线。
3. Mobile Data Agent：冻结手机 SQLite schema、迁移策略、DAO/repository、分页、统计、软删除、恢复和备份方案。
4. Classification Migration Agent：把 Web Prototype 中已验证的解析规则迁移成 Dart 设计，并建立案例对照。
5. Flutter UI Agent：设计和实现手机首页、账单列表、账目确认/编辑页、错误提示、撤销提示和备份入口。
6. Mobile Data / Classification 实现：在 `mobile/` 内实现 Dart 业务逻辑、SQLite 和解析器。
7. App Integration：主 Agent 串联 UI、解析、数据层、统计、备份和错误状态。
8. Android Build Agent：配置 APP 名称、图标、最小权限、Manifest、签名和 APK 构建。
9. Mobile Test Agent：运行 Dart 单测、Widget 测试、SQLite 持久化测试、备份测试和 APK 安装验证。
10. Mobile Review Agent：独立审查范围、架构、数据、权限、测试和 APK 交付证据。
11. APK Delivery：交付可安装 APK，并记录构建命令、文件路径、安装和打开验证。
12. Android APP V1 Complete：只有真机安装、桌面图标、点击打开、离线记账、关闭重开仍有数据、统计正确和本地备份全部通过后才能标记完成。

## 16. 已产生的正式文档

### Web Prototype 文档

- `docs/product-v1.md`：V1 产品需求基线。
- `docs/technical-research.md`：Web Prototype 技术方案调研。
- `docs/data-model.md`：Transaction 和 SQLite 数据模型基线。
- `docs/classification-rules.md`：一句话解析与分类规则。
- `docs/ui-plan.md`：Web Prototype 用户体验与页面方案。
- `docs/api-contract.md`：Web Prototype 前后端 API 契约。
- `docs/integration-report.md`：Web Prototype 前后端联调报告。
- `docs/test-report.md`：Web Prototype 独立测试报告。
- `docs/review-report.md`：Web Prototype 最终独立 Review 报告。
- `docs/review-fix-report.md`：Web Prototype Review 一般问题修复报告。

### Android APP V1 文档

- `docs/android-v1-plan.md`：Android APP V1 阶段总说明。
- `docs/mobile-architecture.md`：Flutter APP 架构、状态管理、SQLite 技术路线、权限原则、模块边界和后续 Agent 文件所有权。
- `docs/android-build-report.md`：Android 开发环境恢复、Flutter 骨架、Manifest 权限、构建验证和 Debug APK 路径记录。
- `docs/mobile-data-model.md`：Android APP V1 本地 SQLite 数据模型、Repository/Data Source、迁移、测试和 Debug APK 回归报告。
- `docs/classification-dart-migration.md`：Android APP V1 一句话 Parser 和分类规则 Dart 迁移报告。
- `docs/release/v1-development-summary.md`：V1 完整开发总结和冻结基线。
- `docs/release/production-release-report.md`：Release 签名构建、APK/AAB、权限和产物校验报告。
- `docs/release/uat-checklist.md`：目标 Android 真机 UAT 清单。
- `docs/android-v2-plan.md`：V2 开发启动条件、V1 兼容不变量和迁移门槛。

## 17. V1 归档与 V2 前置状态

V1 当前已经冻结，相关代码和文档位于同一个项目根目录：

- Android 源码、测试和构建配置：`mobile/`
- 项目和阶段文档：`PROJECT.md`、`docs/`
- Web Prototype：`frontend/`、`backend/`
- Release APK：`mobile/build/app/outputs/flutter-apk/app-release.apk`
- Release AAB：`mobile/build/app/outputs/bundle/release/app-release.aab`

当前 Git 归档基线：

- `v1.0.0`：原始 V1 版本标签。
- `v1.0.0-frozen`：包含最终 V1 文档和 Release 配置的冻结标签。

进入 V2 前必须：

1. 从 `v1.0.0-frozen` 创建独立 V2 分支。
2. 先建立 V2 产品需求、数据迁移、权限隐私和测试文档。
3. 保留 V1 的 `amount_cents`、`type`、`original_text`、软删除和备份兼容性。
4. 不直接修改 V1 冻结提交，不修改 `frontend/` 和 `backend/` 的 Web Prototype。
5. 目标 Android 真机仍需按 `docs/release/uat-checklist.md` 完成 UAT。
6. 以 `docs/android-v2-plan.md` 作为 V2 启动门槛；当前移动端 V1 实际备份格式为 JSON，早期 SQLite 备份描述属于历史设计口径，V2 必须先完成兼容决策。

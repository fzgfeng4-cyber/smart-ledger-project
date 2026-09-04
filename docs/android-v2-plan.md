# Smart Ledger Android APP V2 阶段总计划

## 1. 文档定位

本文是 Smart Ledger Android APP V2 的阶段总计划。V2 不重做 V1，不覆盖 V1 冻结基线；具体版本、子步骤、提示词、并行关系和验收门槛统一记录在 `docs/android-v2-execution-prompts.md`。

V1 的代码、自动化验证和 Release 构建已经完成。当前仍未完成的是目标 Android 真机安装和设备级 UAT，这属于 V1 发布验收事项，不改变 V1 作为 V2 开发基线的事实。

## 2. V1 基线

V2 以以下内容作为基线：

- Android APP V1 技术栈：Flutter + Dart + 本地 SQLite。
- applicationId / namespace：`com.fzgfeng4.smartledger`。
- Android `minSdk`：24。
- V1 冻结标签：`v1.0.0-frozen`。
- V1 原始代码和 Release 配置冻结提交：`2811abe3c8b7eac69c17edd588831e94414a0ea6`。
- 当前文档同步提交：仅同步 V1 状态和发布归档，不改变 V1 业务代码。
- V1 代码目录：`mobile/`。
- Web Prototype：`frontend/` 和 `backend/`，继续保留，不作为 Android APP 运行依赖。

V2 应在文档同步提交完成后使用独立分支 `v2-development`。不得直接在 `v1.0.0-frozen` 标签上开发，也不得修改 V1 冻结标签指向。

## 3. V1 必须继续保持的不变量

除非经过明确的 V2 产品、数据迁移和测试决策，以下规则不得改变：

- `amount_cents` 是唯一金额真相，使用正整数分。
- `type` 只使用 `expense` 和 `income`。
- `category` 使用稳定内部 code。
- 用户确认前，解析结果只能是草稿，不能写入正式账目。
- `original_text` 保存最初原始输入，普通编辑不得覆盖。
- 删除使用 `deleted_at` 软删除。
- 列表和统计默认排除软删除记录。
- V1 数据必须可以被 V2 读取，或必须提供明确、可测试的迁移方案。
- 核心离线记账不依赖 FastAPI、Python、localhost、浏览器或云端服务。
- 不在 V2 中偷偷加入 V1 未批准的权限或外部数据采集。

## 4. V1 实际兼容事实

### 4.1 数据库

V1 移动端实际数据库：

- 文件名：`smart-ledger.sqlite`
- 数据库版本：`1`
- 核心表：`transactions`
- 当前字段：`id`、`amount_cents`、`type`、`category`、`note`、`original_text`、`transaction_date`、`created_at`、`updated_at`、`deleted_at`

V2 如果增加字段或表，必须使用正式 SQLite migration，不得删除数据库重建，也不得静默丢弃旧字段。

### 4.2 备份

V1 移动端当前实际使用 `BackupService` 生成 JSON 备份，备份根对象包含：

- `backup_version`
- `app_version`
- `database_version`
- `created_at`
- `transactions`

当前实际备份格式为 `backup_version = 1`、`database_version = 1`，文件扩展名为 `.json`，并且包含有效记录和软删除记录。

部分早期 Web/架构文档曾描述 SQLite 文件安全备份。这是历史设计口径，与当前 Android V1 实际 JSON 实现不同。V2 不得静默把两种格式当成同一种格式；任何备份改动必须明确：

1. 是否继续兼容 V1 JSON 备份。
2. 是否新增 SQLite 备份格式。
3. 两种格式的识别、导入、错误提示和测试方式。
4. 旧备份恢复失败时如何保护当前账本不被清空。

## 5. V2 开发门槛

正式编写 V2 功能前，必须完成：

1. 确定一个明确的 V2 第一功能和用户问题。
2. 写出 V2 产品需求、非目标和停止线。
3. 判断是否需要新增数据字段、数据库表或 migration。
4. 制定 V1 数据和备份兼容方案。
5. 判断新增 Android 权限、隐私风险和数据去向。
6. 写出可执行的 V2 测试案例和回归范围。
7. 先完成文档 Review，再开始实现。

未满足以上条件时，只允许做调研、原型或文档，不进入正式业务代码开发。

## 6. V2 范围边界

V2 仍然不得默认加入：

- 微信、支付宝、淘宝或银行自动读取。
- 通知、短信、通讯录、无障碍或后台采集。
- OCR、相机或相册读取。
- 云同步、登录注册、多用户。
- 未经确认的自动记账。
- 直接修改或删除 V1 历史数据。

如果 V2 选择其中某项作为正式目标，必须先完成单独的权限、隐私、数据来源、用户授权和迁移设计。

## 7. 推荐的最小 Agent 分工

V2 不为了数量增加角色，保留以下职责：

| Agent | 主要职责 |
| --- | --- |
| 主 Agent | 阶段控制、范围、跨模块集成和最终验收。 |
| V2 Product/Scope Agent | 第一功能、用户流程、非目标和停止线。 |
| V2 Data/Migration Agent | SQLite migration、V1 数据兼容、备份格式和恢复安全。 |
| V2 UI/Implementation Agent | 只有在功能范围确定后实现对应 UI 和业务。 |
| V2 Test/Review Agent | 回归测试、权限检查、APK 验证和独立审查。 |

是否拆分 UI 和 Implementation，等 V2 第一功能确定后再决定。

## 8. 当前准备进度

- [x] V1 代码和自动化测试完成。
- [x] V1 Release APK/AAB 已生成并完成签名校验。
- [x] V1 冻结标签已建立。
- [x] V1 项目状态文档已同步到工作区。
- [x] V2 阶段总计划已建立。
- [x] V2 独立分支已建立：当前分支为 `v2-development`。
- [x] V2 第一功能已确定：批量记账和首页组合搜索。
- [x] V2 产品需求、非目标和停止线已建立：见 `docs/android-v2-execution-prompts.md`。
- [x] V2.2-V2.6 各版本的数据和备份迁移方案已完成并经过当前版本测试。
- [x] V2.4-V2.6 的权限与隐私方案已完成；V2.6 仅增加用户主动 OCR 所需的相机权限。
- [x] V2 分版本测试门槛已建立：每个步骤必须有针对性测试和主 Agent 复核。
- [x] V2.6 已完成发布收尾并冻结，后续新增需求转入 V3。

## 9. 下一步

文档同步提交已完成，主 Agent 已建立并切换到 `v2-development` 分支。V2.1 的批量记账和首页搜索已在当前工作区落地，下一阶段按 `docs/android-v2-execution-prompts.md` 从 V2.2.1 开始推进。

每个版本都必须遵循：单独提示词 -> 子任务执行 -> 主 Agent 检查文件边界和测试证据 -> 版本验收 -> 才能进入下一版本。V2.6 已完成并冻结；后续应先为 V3 重新建立需求、数据迁移、权限隐私和测试方案。

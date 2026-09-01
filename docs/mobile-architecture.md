# Smart Ledger Android APP V1 移动端架构设计

## 1. 文档定位

本文是 Smart Ledger Android APP V1 的移动端架构设计文档，供后续 Mobile Data Agent、Classification Migration Agent、Flutter UI Agent、Android Build Agent、Mobile Test Agent、Mobile Review Agent 和主 Agent 共同读取。

当前阶段只做架构设计：

- 已确认：Android APP V1 使用 Flutter + Dart + APP 内部业务逻辑 + 手机本地 SQLite。
- 已确认：Android APP V1 运行时不依赖浏览器、Python、FastAPI、localhost 或外部 Backend。
- 已确认：识别结果先成为待确认草稿，用户确认后才保存为正式账目。
- 建议：后续在获得主 Agent 明确授权后，通过标准 Flutter 工具创建 `mobile/`。
- 未验证：本轮未运行本机 `flutter --version`、`flutter doctor`、Android SDK 或真机检查。
- 后续阶段：本文不创建 `mobile/`，不实现页面，不迁移解析代码，不创建正式 SQLite 数据库，不构建 APK。

## 2. 已读取依据

本设计依据以下项目文档和规则：

- `PROJECT.md`
- `docs/android-v1-plan.md`
- `docs/product-v1.md`
- `docs/data-model.md`
- `docs/classification-rules.md`
- `docs/ui-plan.md`
- `skills/mobile-architecture.md`

`frontend/` 和 `backend/` 只作为 Web Prototype 的历史参考；Android V1 不复用其运行时。

## 3. 技术基线建议

### 3.1 Flutter 与 Dart

建议 Android APP V1 使用 Flutter stable channel，并使用 Flutter SDK 自带的 Dart SDK，不单独绑定一个孤立 Dart 安装。

基线原则：

| 项目 | 建议 |
| --- | --- |
| Flutter SDK | 使用创建 `mobile/` 时本机可用的 Flutter stable 版本；Android Build Agent 需要记录 `flutter --version`。 |
| Dart | 使用 Flutter stable 随附的 Dart 3.x；`pubspec.yaml` 的 `environment` 由 `flutter create` 生成后再由 Android Build Agent 复核。 |
| 版本锁定 | V1 不在本文硬编码具体补丁号；构建阶段以本机工具链实测结果和 Flutter 官方支持矩阵为准。 |
| 本轮状态 | 未验证本机是否已安装 Flutter、Android Studio、Android SDK、构建工具或已接受 Android licenses。 |

公开资料显示，截至 2026-08-30 查询时，Flutter 官方支持矩阵已把 Android API 24 到 37 列为支持范围，API 24 到 36 为 CI 测试范围。因此 V1 不建议为了兼容很旧手机而把 `minSdk` 压到 Flutter 当前支持线以下。

### 3.2 Android SDK

| 配置 | 架构建议 | 说明 |
| --- | --- | --- |
| `minSdk` | 建议 API 24 起步 | 覆盖当前 Flutter 支持和 CI 测试范围，减少旧系统兼容成本。若用户明确要支持更旧手机，必须重新评估插件和真机风险。 |
| `targetSdk` | 建议跟随当前 Flutter/Android stable 默认值，并在构建前确认不低于当前发布要求 | 从 2026-08-31 起，Google Play 新应用和更新要求 target Android 16 / API 36 或更高；即使 V1 先本地安装，也不要故意降低 target。 |
| `compileSdk` | 使用 Flutter Gradle 默认值或本机安装的最新稳定 Android SDK | `targetSdk` 不应高于可用 `compileSdk`。Android Build Agent 负责实测。 |
| NDK/Gradle | 先使用 `flutter create` 模板默认配置 | V1 没有自定义原生能力，不提前改复杂 Android 构建链。 |

### 3.3 applicationId、namespace、包名与 APP 名称

建议：

| 项目 | 建议值 |
| --- | --- |
| APP 显示名称 | `Smart Ledger` |
| Android `applicationId` | `com.fzgfeng4.smartledger` |
| Android `namespace` | `com.fzgfeng4.smartledger` |
| Kotlin/Java 包路径 | 与 `namespace` 保持一致 |
| Dart package 名称 | 可用 `smartledger` 或 `smart_ledger`，由 `flutter create` 实际约束决定 |

说明：

- `applicationId` 是 Android 设备和发布渠道识别 APP 的关键值，发布后不应随意修改。
- 如果用户后续希望使用个人姓名拼音或正式域名反向命名，必须在创建 `mobile/` 前确认。
- APP 名称只用于用户看到的桌面图标和系统应用名称，不等同于 `applicationId`。

### 3.4 建议创建方式与停止点

后续 Android Build Agent 或主 Agent 获得授权后，建议通过标准 Flutter 模板创建项目：

```text
flutter create --platforms=android --org com.fzgfeng4 --project-name smartledger mobile
```

停止点：

- 只生成 Flutter Android 项目骨架。
- 立即检查 `applicationId`、`namespace`、APP label 是否符合本文。
- 不在创建项目时顺手实现页面、数据库、解析器或 APK 发布。
- 如果模板生成的包名与 `com.fzgfeng4.smartledger` 不一致，Android Build Agent 应在专属阶段调整并记录。

## 4. 最终内部架构

Android APP V1 的运行架构固定为：

```text
Flutter UI
  -> Application / Service
  -> Repository
  -> SQLite
```

一句话记账的数据流固定为：

```text
一句话输入
  -> Transaction Parser
  -> Classification Rules
  -> 待确认 Transaction 草稿
  -> 用户确认或修改
  -> Repository
  -> SQLite
```

架构不变量：

- UI Page 不直接写 SQL。
- UI Page 不直接创建、打开或迁移 SQLite 文件。
- Parser 不保存数据，不读取数据库。
- Repository 隐藏 SQLite 细节，对上层提供账目读写、统计和备份所需的数据访问能力。
- Service 负责串联业务流程、校验保存闸门、处理重复提醒、刷新页面状态。
- 待确认草稿不进入账单列表，不计入统计，不进入备份。

## 5. 分层职责

| 层 | 职责 | 禁止事项 |
| --- | --- | --- |
| UI Page | 展示首页、账单列表、账目工作页；接收输入；展示草稿、错误、撤销和备份状态。 | 不写 SQL；不拼接数据库路径；不绕过确认直接保存；不复制分类常量。 |
| UI State / Controller | 持有页面临时状态，例如当前输入、ParseResult、加载状态、错误提示。 | 不做 SQLite 细节；不把草稿伪装成已保存账目。 |
| Application / Service | 编排解析、校验、保存、编辑、删除、撤销、统计刷新、备份。 | 不直接操作 SQLite 连接；不引入网络、OCR、通知或后台任务。 |
| Domain | 定义账目模型、草稿模型、分类目录、金额和日期规则、解析器契约。 | 不依赖 Flutter Widget；不依赖 SQLite 插件。 |
| Repository | 提供账目 CRUD、分页、统计聚合、重复提醒查询和软删除恢复。 | 不暴露 SQL 给 UI；不返回已删除记录给普通列表。 |
| SQLite Data Source | 管理数据库连接、schema、索引、迁移和参数绑定查询。 | 不承载页面状态；不做自然语言解析。 |
| BackupService | 生成 SQLite 一致性备份快照，并交给 Android 系统保存/分享机制。 | 不申请宽泛存储权限；不做云同步；不做恢复中心。 |

## 6. 核心数据模型边界

### 6.1 LedgerTransaction 与 ParseResult 分开

Dart 中必须把待确认草稿和已保存正式账目分开。

| 模型 | 含义 | 字段完整性 | 是否入库 |
| --- | --- | --- | --- |
| `ParseResult` | 解析器给出的待确认结果和提示 | 允许 `amount_cents`、`type`、`category`、`transaction_date` 暂缺；可包含状态、候选项和提示 | 不入库 |
| `LedgerTransaction` | 用户确认后保存的正式账目 | `amount_cents`、`type`、`category`、`original_text`、`transaction_date`、`created_at`、`updated_at` 等关键字段必须完整 | 入库 |

必须保留的正式 Transaction 十字段：

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

建模原则：

- `ParseResult` 可以表达“缺金额”“方向未知”“分类待确认”“多金额”等状态。
- `LedgerTransaction` 不允许关键字段缺失，不接受未处理歧义。
- UI 编辑的是草稿或正式账目的可编辑副本；只有保存成功后才更新正式账。
- 普通编辑不修改 `original_text`，除非用户回到输入阶段重新解析并保存一笔新账。

### 6.2 金额整数分

`amount_cents` 是金额真相，使用整数分保存和计算。

| 场景 | 规则 |
| --- | --- |
| 用户输入 | UI 接收“元”口径字符串，例如 `35`、`35.8`、`35.80`。 |
| 转换层 | Money 工具把元字符串转换为正整数分；最多两位小数；不使用 `double` 做核心财务计算。 |
| 数据库 | SQLite 保存 `amount_cents INTEGER`，例如 35 元保存为 `3500`。 |
| 统计 | Repository / Summary 使用整数分做 SUM。 |
| UI 展示 | 格式化层把整数分展示为人民币，例如 `¥35.00`。 |

禁止：

- 用 `double` 作为数据库金额或统计金额的核心类型。
- 用负数金额表达支出。
- 0 或负数静默修正为有效金额。
- 小数超过两位时静默四舍五入或截断。

## 7. 分类常量唯一来源

分类目录只保留一份，建议放在 Domain 层，例如：

```text
mobile/lib/domain/categories/category_catalog.dart
```

这份目录应同时提供：

- `type` 与 `category` code 的合法组合。
- code 到中文名称的展示映射。
- Parser 使用的分类 code。
- UI 分类选择器使用的分类列表。
- Repository 保存前的分类校验依据。

禁止：

- Parser 维护一份分类表，UI 再复制一份分类表。
- 数据库存中文分类名作为主值。
- 在 V1 中增加用户自定义分类。
- 临时新增 `category_name`、`displayCategory` 等第二套主字段。

## 8. 一句话解析模块契约

解析模块只做“从一句话生成待确认建议”，不做保存。

概念契约：

| 模块 | 输入 | 输出 | 说明 |
| --- | --- | --- | --- |
| Transaction Parser | `original_text`、当前本机日期、分类目录 | `ParseResult` | 保留原句，识别金额、方向、分类、备注、日期和状态。 |
| Classification Rules | 解析副本、关键词表、分类目录 | 分类建议、候选项、冲突提示 | 输出稳定 category code，不输出中文名作为主值。 |
| Validation | 草稿或用户确认后的字段 | 字段错误、保存阻塞原因 | 金额、日期、分类与 type 匹配、长度和歧义状态都在保存前检查。 |

`ParseResult` 建议包含这些概念字段：

| 字段 | 说明 |
| --- | --- |
| `original_text` | 用户提交用于解析的完整原句。 |
| `amount_cents` | 可缺失；金额候选明确时为正整数分。 |
| `type` | 可缺失；最终只允许 `expense` 或 `income`。 |
| `category` | 可缺失或为兜底 code；需要标记是否待确认。 |
| `note` | 可为空；来自解析建议，用户可改。 |
| `transaction_date` | 可缺失或未来待修改；保存前必须是有效今天或历史日期。 |
| `status` | `ready`、`needs_confirmation`、`needs_input`、`no_draft`。 |
| `issues` | 给 UI 的中文提示依据，例如缺金额、多金额、分类冲突、未来日期。 |
| `candidates` | 可选候选项，例如多个分类候选；不是数据库字段。 |

后续 Classification Migration Agent 只迁移规则和测试案例，不改变保存模型，不自动拆分多笔，不接入 AI。

## 9. 状态管理方案

### 9.1 方案比较

| 方案 | 优点 | 缺点 | 是否推荐 |
| --- | --- | --- | --- |
| `setState` | 零依赖、学习成本低 | 三个页面共享统计、列表刷新、撤销、备份状态时容易散落 | 不推荐作为全局方案 |
| `Provider + ChangeNotifier` | 简单、可测试、无代码生成，适合 3 个核心页面和本地数据 | 需要约束 Controller 职责，避免把业务逻辑塞进 UI 状态 | 推荐 |
| Riverpod | 依赖管理清晰，扩展性更强 | 对 V1 新手项目偏重，概念和样板更多 | 暂不推荐 |
| BLoC / Redux | 状态流严格，适合复杂协作 | 对本地个人记账 V1 明显过度设计 | 不推荐 |

### 9.2 V1 推荐

V1 推荐 `Provider + ChangeNotifier`。

边界：

- Page 订阅 Controller 状态并触发用户动作。
- Controller 调用 Service，不直接写 SQL。
- Service 调用 Repository，不持有 Widget 上下文。
- Repository 返回领域对象或结果对象，不返回 SQLite cursor。

建议的 Controller：

| Controller | 负责 |
| --- | --- |
| `HomeController` | 首页统计、最近账目、快速输入状态。 |
| `TransactionListController` | 账单分页、加载更多、刷新和读取失败状态。 |
| `TransactionEditorController` | 新增确认、编辑、字段校验、保存、删除、撤销状态。 |
| `BackupController` | 备份入口的准备中、成功、失败提示。 |

## 10. SQLite 技术路线

### 10.1 方案比较

| 方案 | 优点 | 缺点 |
| --- | --- | --- |
| `sqflite` | Flutter 移动端常见 SQLite 插件；直接、轻量；一张表和简单查询足够；没有强制代码生成。 | SQL 字符串需要 Repository/Data Source 严格集中管理；类型安全弱于 drift；备份机制需要在 Mobile Data 阶段实测。 |
| `drift` | 类型安全更好；迁移和测试结构更强；适合复杂查询增长。 | 代码生成和概念更多；V1 只有一张核心表时偏重；容易引入架构复杂度。 |
| `sqlite3` / FFI 路线 | 可控性强，可能更方便使用底层 SQLite 能力。 | Android 集成和依赖判断更复杂；不适合作为新手 V1 的第一选择。 |

### 10.2 V1 推荐

V1 架构推荐 `sqflite`，配合 Repository/Data Source 集中管理 SQL。

理由：

- 当前只有一张 `transactions` 表和少量聚合查询。
- 不需要分类表、用户表、同步表或复杂 join。
- 避免 drift 代码生成和过重抽象。
- 后续如果 V2 引入导入、同步、更多表或复杂迁移，再重新评估 drift。

约束：

- SQL 只能写在 Data Source 或 Repository 内。
- 所有参数使用绑定，不拼接用户输入。
- 所有普通查询默认过滤 `deleted_at IS NULL`。
- Mobile Data Agent 必须实测并记录 SQLite 备份的一致性方案；如果 `sqflite` 不能满足安全备份验收，再由主 Agent 决定是否更换底层路线。

## 11. SQLite 文件与备份架构

### 11.1 数据库文件

默认数据库文件放在 APP 私有目录。

建议：

| 项目 | 建议 |
| --- | --- |
| 数据库文件名 | `smart-ledger.sqlite` |
| 存放位置 | Android APP 私有应用数据目录，由 `path_provider` 或 SQLite 插件推荐路径获取。 |
| 用户可见性 | 默认不可直接在文件管理器中浏览，避免误删和权限问题。 |
| 数据安全 | 关闭 APP 后仍保留；卸载 APP 时由 Android 系统清理私有数据。 |

备份文件和内部数据库必须分开：

- 内部数据库是 APP 运行主库。
- 备份文件是某一时间点导出的副本。
- 用户保存或分享的是备份副本，不是正在运行的主库文件。

### 11.2 备份架构

备份数据流：

```text
UI
  -> BackupService
  -> SQLite 一致性备份快照
  -> APP cache / 临时导出文件
  -> Android 系统文件保存或分享机制
  -> 用户选择保存位置或分享目标
```

V1 原则：

- 使用 SQLite 安全备份或等价的一致性快照流程，不能在数据库正在写入时直接复制主库文件。
- 备份文件名建议为 `smart-ledger-backup-YYYYMMDD-HHMMSS.sqlite`。
- 备份包含 `transactions` 表、schema、索引、有效记录和软删除记录。
- 备份不包含未确认草稿、OCR 原图、云端副本、通知内容或外部账号信息。
- 不申请 `MANAGE_EXTERNAL_STORAGE`、相册、媒体读取或其他宽泛存储权限。
- 文件交付优先走 Android 系统分享面板或系统文件保存器；具体 Flutter 包由 Backup/Build 阶段确认。

## 12. 软删除与撤销

V1 使用 `deleted_at` 软删除，数据库不自动物理删除。

行为：

- 删除前必须二次确认。
- 删除成功后设置 `deleted_at` 和 `updated_at`。
- 列表、最近账目、统计和重复提醒只看 `deleted_at IS NULL`。
- 当前页面提供约 10 秒撤销窗口。
- 10 秒内撤销时，把同一行 `deleted_at` 恢复为 `NULL`，保留原 `id`、`created_at`、`original_text` 和业务字段。
- 超过撤销窗口后，页面撤销入口消失，但数据库仍保留软删除行。
- V1 不提供回收站、批量删除、永久清理、30 天自动清理或复杂恢复中心。

实现边界：

- 10 秒计时属于 UI/Service 层交互状态。
- 软删除状态属于数据库正式字段。
- 不把撤销状态写成另一张表。
- 不用物理删除来模拟撤销。

## 13. 统计计算

统计由 `SummaryService` 编排，由 Repository/SQLite 负责聚合计算。

推荐口径：

| 指标 | 计算位置 | 规则 |
| --- | --- | --- |
| 今天支出 | SQLite 聚合 | `deleted_at IS NULL`、`type = expense`、`transaction_date = 今天`。 |
| 本月支出 | SQLite 聚合 | `deleted_at IS NULL`、`type = expense`、`transaction_date` 位于本机当前月份。 |
| 本月收入 | SQLite 聚合 | `deleted_at IS NULL`、`type = income`、`transaction_date` 位于本机当前月份。 |

理由：

- 不把全量账目拉到 UI 后再合计。
- 整数分在 SQLite 中 SUM，适合数据增长。
- 当前只需三个基础指标，不需要缓存层、物化表或复杂报表引擎。
- 编辑、删除、撤销后由 Service 触发相关 Controller 刷新。

## 14. 分页与加载更多

V1 推荐简单分页：

| 项目 | 建议 |
| --- | --- |
| 首页最近账目 | `limit = 5` |
| 账单列表首屏 | `limit = 20` 或 `30` |
| 加载更多 | `limit + offset` |
| 排序 | `transaction_date DESC`，同一天 `updated_at DESC`，再用 `id DESC` 稳定兜底 |

理由：

- 个人本地账本早期数据量有限，`limit/offset` 简单可懂。
- 查询仍应建立合适索引，避免数据增长后列表明显变慢。
- 如果未来达到十万级记录或增加复杂筛选，再评估基于游标的分页。

## 15. 草稿保护规则

继承 Web Review 经验，Android V1 必须保护用户输入和待确认状态。

规则：

- 空输入不生成草稿。
- 解析失败不清空原句。
- 保存失败保留当前草稿字段和用户修改。
- 返回修改原句时，原始输入原样回填。
- 多金额、方向未知、分类待确认、未来日期等状态不得绕过保存闸门。
- 用户未确认前，`ParseResult` 不写入 SQLite，不进入列表，不计入统计，不进入备份。
- APP 被系统杀掉时，V1 不承诺恢复未保存草稿；这不是数据丢失，因为正式账目尚未保存。
- 如果未来要持久化草稿，必须先设计独立草稿模型，不能混入 `transactions` 正式表。

## 16. 页面结构

Android V1 继续沿用 3 个核心页面：

| 页面 | 职责 |
| --- | --- |
| 首页 | 三个基础统计、快速记账入口、最近 5 笔账目、备份入口菜单。 |
| 账单列表 | 全部有效账目、分页/加载更多、进入新增或编辑。 |
| 账目工作页 | 新增输入/确认、字段修改、编辑已保存账目、删除确认、10 秒撤销。 |

不新增：

- 设置页
- 独立详情页
- 登录页
- 同步页
- OCR 页
- AI 聊天页
- 报表中心
- 导入中心
- 回收站

备份入口仍放在全局“更多”或页面右上角菜单，不单独建立设置页。

## 17. 路由方案

### 17.1 方案比较

| 方案 | 优点 | 缺点 | 结论 |
| --- | --- | --- | --- |
| Flutter 内置 `Navigator` / named routes | 零新增路由依赖；适合 3 个页面；新手容易维护。 | 深链、嵌套路由和复杂重定向能力弱。 | V1 推荐 |
| `go_router` | 声明式路由、深链和重定向能力强。 | 当前没有登录、深链、底部多栈导航，属于偏重依赖。 | 暂不推荐 |
| `auto_route` | 类型化路由和生成能力强。 | 需要代码生成，对 V1 过度。 | 不推荐 |

### 17.2 V1 推荐

V1 使用 Flutter 内置 `Navigator` 和简单 named routes：

- `/`：首页
- `/transactions`：账单列表
- `/transaction/new`：账目工作页新增/确认状态
- `/transaction/edit`：账目工作页编辑状态，通过参数传入 `id`

如果未来 V2 增加导入流程、深链、登录或多栈导航，再评估 `go_router`。

## 18. 依赖清单原则

V1 只加入完成离线记账闭环必要的依赖。

建议依赖类型：

| 类型 | 候选 | 用途 |
| --- | --- | --- |
| 状态管理 | `provider` | `ChangeNotifier` 注入和页面订阅。 |
| SQLite | `sqflite` | 手机本地 SQLite CRUD 和聚合查询。 |
| 路径 | `path_provider` | 获取 APP 私有目录和临时导出目录。 |
| 备份交付 | Android SAF / `ACTION_CREATE_DOCUMENT` 平台通道，或经验证支持 Android 保存位置选择的插件；`share_plus` 只作为分享导出备选 | 通过 Android 系统保存/分享机制交付备份副本。后续阶段必须实测插件能力，不能用宽泛存储权限代替系统文件选择。 |
| 格式化 | 可选 `intl` | 人民币和日期展示格式；若不用也必须集中到 shared formatter。 |
| 测试 | `flutter_test`、`integration_test`、可选 `sqflite_common_ffi` | 单元、Widget、Repository 和集成测试。 |

明确不加入：

- OCR 包
- 网络请求包
- 通知包
- 权限管理包
- 相机/相册包
- AI/LLM SDK
- 后台任务包
- Firebase/登录/云同步包
- 支付平台 SDK
- 复杂图表包

如果某个备份交付插件间接申请不必要权限，应停止并更换方案。

补充约束：

- Android 的“让用户选择保存位置”优先按 Storage Access Framework 思路处理。
- 如果选择 Flutter 插件，Mobile Data Agent 或 Android Build Agent 必须确认该插件在 Android 上支持创建文件或保存位置选择；不能只看桌面端能力。
- `share_plus` 可以满足“把备份文件交给用户”的轻量导出，但不等同于强制用户选择某个本地保存路径。

## 19. Android 权限

V1 默认应做到 0 个特殊危险权限。

| 权限 | V1 是否需要 | 说明 |
| --- | --- | --- |
| `INTERNET` | 不需要 | V1 离线运行，不调用 FastAPI、localhost、AI API 或云服务。`INTERNET` 不是危险权限，但 release Manifest 也不应声明。 |
| 存储读取/写入 | 不需要 | 数据库在 APP 私有目录；备份通过系统保存/分享机制。 |
| 相机 | 不需要 | OCR/拍照不属于 V1。 |
| 相册/媒体 | 不需要 | 截图识别和账单导入不属于 V1。 |
| 通知 | 不需要 | 通知读取和提醒不属于 V1。 |
| 短信/通讯录 | 不需要 | 不采集外部数据。 |
| 后台服务/无障碍 | 不需要 | 不做自动采集。 |

Android Build Agent 必须在构建阶段检查 `AndroidManifest.xml`、合并后的 Manifest 和最终 APK 权限清单。

## 20. 推荐 `mobile/` 目录结构

以下只是建议结构，不表示本轮已经创建目录：

```text
mobile/
├─ pubspec.yaml
├─ android/
├─ lib/
│  ├─ main.dart
│  ├─ app/
│  │  ├─ smart_ledger_app.dart
│  │  └─ app_routes.dart
│  ├─ ui/
│  │  ├─ home/
│  │  ├─ transactions/
│  │  ├─ editor/
│  │  └─ shared/
│  ├─ application/
│  │  ├─ ledger_service.dart
│  │  ├─ summary_service.dart
│  │  └─ backup_service.dart
│  ├─ domain/
│  │  ├─ models/
│  │  ├─ parser/
│  │  ├─ categories/
│  │  └─ validation/
│  ├─ data/
│  │  ├─ sqlite/
│  │  └─ repositories/
│  └─ shared/
│     ├─ clock.dart
│     ├─ money_formatter.dart
│     └─ result.dart
├─ test/
└─ integration_test/
```

大白话解释：

- `main.dart`：APP 入口，只负责启动。
- `app/`：放 APP 外壳、主题、路由和全局依赖装配。
- `ui/`：放用户看得见的页面和组件。
- `application/`：放“点击按钮后到底要串哪些步骤”的业务编排。
- `domain/`：放账目、草稿、分类、金额、日期和解析规则这些核心概念。
- `data/`：放 SQLite、Repository 和数据读写实现。
- `shared/`：放跨层共用但不属于业务模型的小工具，例如时间、金额格式化、结果包装。
- `test/`：放 Dart unit、Widget、Repository 测试。
- `integration_test/`：放真机或模拟器完整流程测试。

## 21. APP 内部模块契约

### 21.1 Parser

| 能力 | 契约 |
| --- | --- |
| 解析一句话 | 输入原句和当前本机日期，输出 `ParseResult`。 |
| 保留原文 | `original_text` 必须是用户提交的完整原句。 |
| 金额转换 | 输出整数分或缺失/非法状态，不输出核心 `double` 金额。 |
| 分类 | 输出固定 category code 和候选项，不写中文名入库。 |
| 状态 | 明确 `ready`、`needs_confirmation`、`needs_input`、`no_draft`。 |
| 禁止 | 不保存 SQLite，不调用 Repository，不联网，不调用 AI。 |

### 21.2 Repository

| 能力 | 契约 |
| --- | --- |
| 新增账目 | 只接受已确认、已校验的正式账目输入，返回带 `id` 和时间戳的 `LedgerTransaction`。 |
| 编辑账目 | 按 `id` 更新原行，保留 `created_at` 和 `original_text`，更新 `updated_at`。 |
| 软删除 | 设置 `deleted_at`，不物理删除。 |
| 撤销删除 | 同一行恢复 `deleted_at = NULL`，更新 `updated_at`。 |
| 列表分页 | 默认只返回未删除记录，支持 `limit/offset`。 |
| 最近账目 | 返回最近 5 笔未删除记录。 |
| 重复提醒查询 | 只比较最近一笔未删除账的日期、金额、type、category、note。 |

### 21.3 Summary

| 能力 | 契约 |
| --- | --- |
| 首页统计 | 返回今天支出、本月支出、本月收入，单位都是整数分。 |
| 日期口径 | 使用 `transaction_date`，不使用 `created_at` 代替账务日期。 |
| 删除口径 | 排除 `deleted_at` 非空记录。 |
| 展示 | UI 格式化为人民币，Summary 不返回浮点财务结果。 |

### 21.4 Backup

| 能力 | 契约 |
| --- | --- |
| 创建备份 | 生成一致性的 SQLite 备份副本。 |
| 文件名 | `smart-ledger-backup-YYYYMMDD-HHMMSS.sqlite`。 |
| 文件交付 | 交给 Android 系统保存或分享机制。 |
| 权限 | 不申请不必要存储权限。 |
| 范围 | 不做恢复中心、不做云备份、不做定时后台备份。 |

## 22. 测试架构

后续测试按风险分层，不把“能启动”当作数据正确。

| 测试层 | 责任 | 示例 |
| --- | --- | --- |
| Dart unit | 测 Parser、金额转换、日期规则、分类目录、保存校验。 | 20 个解析案例、0/负数/小数超过两位、多金额、未来日期。 |
| SQLite / Repository | 测 schema、CRUD、软删除、撤销、分页、统计、重复提醒、备份快照。 | 编辑不改 `original_text`；统计排除软删除；关闭重开后数据仍在。 |
| Widget | 测 3 个页面的关键状态和按钮启用/禁用。 | `needs_input` 禁用保存；兜底分类需确认；删除后显示撤销。 |
| Integration | 测 APP 内完整链路。 | 输入一句话 -> 确认 -> 保存 -> 列表 -> 编辑 -> 删除 -> 撤销 -> 备份。 |
| APK / 真机 | 测最终安装和 Android 行为。 | 桌面图标、点击打开、离线可用、权限清单、关闭重开持久化。 |

验收口径：

- 解析通过不代表保存通过。
- 单元测试通过不代表 APK 可安装。
- APK 可安装不代表权限正确。
- 本地模拟器通过不代表真机已验证。
- 备份文件存在不代表备份一致性已验证。

## 23. V2 边界

当前模块设计不应阻碍未来扩展，但 V1 绝不实现未来能力。

未来可能扩展：

| 方向 | 当前边界 |
| --- | --- |
| 账单导入 | 未来导入结果也应先生成 `ParseResult` 或类似待确认草稿；当前不加导入包、不加来源字段。 |
| OCR | 未来 OCR 只能作为输入来源，不能绕过用户确认；当前不加相机、相册、OCR 包。 |
| 通知/短信 | 未来必须先做权限、合规和用户授权设计；当前不加通知、短信、后台服务、无障碍。 |
| AI 分类 | 未来可作为 Parser 的辅助建议器；当前不加 AI SDK、不联网、不上传 `original_text`。 |
| 云同步 | 未来需要账号、冲突、加密和备份策略；当前不加登录、网络或同步字段。 |

架构保留的是接口边界，不是隐藏实现。任何 V2 能力都必须先更新产品、数据、权限和测试文档。

## 24. 后续 Agent 文件所有权与执行顺序

### 24.1 文件所有权

| Agent | 文档所有权 | 后续代码所有权建议 |
| --- | --- | --- |
| 主 Agent | `PROJECT.md`、阶段总控文档、最终验收报告 | 跨模块集成协调，不直接抢写各 Agent 专属文件。 |
| Mobile Architecture Agent | `docs/mobile-architecture.md` | 后续如获授权，可创建或调整架构骨架，但本轮不做。 |
| Mobile Data Agent | `docs/mobile-data-model.md` | `mobile/lib/data/`、Repository、SQLite schema、迁移、备份底层。 |
| Classification Migration Agent | `docs/classification-dart-migration.md` | `mobile/lib/domain/parser/`、`mobile/lib/domain/categories/` 中解析和分类规则。 |
| Flutter UI Agent | `docs/mobile-ui-plan.md` | `mobile/lib/ui/`、Controller 和页面组件；不写 SQL。 |
| Android Build Agent | `docs/android-build-report.md` | `mobile/android/`、Manifest、label、图标、签名、APK 构建。 |
| Mobile Test Agent | `docs/mobile-test-report.md` | `mobile/test/`、`mobile/integration_test/`。 |
| Mobile Review Agent | `docs/mobile-review-report.md` | 只读审查，除非主 Agent 单独授权修复。 |

### 24.2 执行顺序

推荐顺序：

1. 主 Agent 确认本文架构。
2. Android Build Agent 或主 Agent 创建标准 Flutter `mobile/` 骨架，并检查包名、APP 名称和权限初始状态。
3. Mobile Data Agent 细化 SQLite schema、Repository、迁移、分页、统计和备份一致性方案。
4. Classification Migration Agent 迁移 Dart 解析规则与案例。
5. Flutter UI Agent 实现 3 个核心页面和草稿确认状态。
6. 主 Agent 做 App Integration，串联 UI、Service、Repository、Parser、Backup。
7. Mobile Test Agent 运行 Dart、SQLite、Widget、Integration 和 APK/真机测试。
8. Android Build Agent 生成最终 APK，记录构建命令、签名和产物路径。
9. Mobile Review Agent 做独立最终审查。
10. 主 Agent 汇总 Android APP V1 是否达到完成标准。

可并行：

- Mobile Data 文档细化和 Classification Migration 文档细化可以在本文确认后并行，但必须共享 `LedgerTransaction`、`ParseResult` 和分类目录边界。
- Flutter UI 设计可以与 Data 设计并行，但 UI 实现必须等保存契约稳定。

必须串行：

- `mobile/` 骨架创建必须在主 Agent 确认后进行。
- Repository/SQLite 实现必须在 Mobile Data 设计后进行。
- Parser 完整迁移必须在分类常量唯一来源确认后进行。
- APK 构建必须在基础功能集成后进行。
- Mobile Review 必须在实现和测试证据之后进行。

## 25. 架构验收标准

本文完成后，只能视为架构设计完成，不代表 Android APP 已实现。

后续进入实现前，应确认：

- Flutter/Dart/Android SDK 基线已由 Android Build Agent 本机实测。
- `mobile/` 创建命令和 `applicationId` 已由主 Agent 确认。
- `LedgerTransaction` 与 `ParseResult` 分离无争议。
- 分类目录唯一来源已确认。
- SQLite 技术路线和备份验收门槛已确认。
- Android release Manifest 默认不声明不必要权限。
- 后续 Agent 的文件所有权已确认。

## 26. 本轮未做

本轮没有：

- 创建 `mobile/`。
- 修改 `frontend/`。
- 修改 `backend/`。
- 创建 Android APK。
- 创建 SQLite 正式数据库。
- 实现 Flutter 页面。
- 实现 Dart Parser。
- 运行本机 Flutter/Android 工具链验证。

## 27. 资料来源与后续复核点

本文涉及 Flutter、Android SDK、SQLite、状态管理和 Android 文件保存机制的版本性判断，应在创建 `mobile/` 和构建 APK 前由 Android Build Agent 用本机环境重新记录。

已参考的公开资料：

- Flutter 官方 Android 部署文档：https://docs.flutter.dev/deployment/android
- Flutter 官方支持平台矩阵：https://docs.flutter.dev/reference/supported-platforms
- Android 官方 target SDK 要求：https://developer.android.google.cn/google/play/requirements/target-sdk?hl=zh-cn
- Flutter 官方 SQLite cookbook：https://docs.flutter.dev/cookbook/persistence/sqlite
- `sqflite` 官方 pub.dev 页面：https://pub.dev/packages/sqflite
- Flutter 官方状态管理说明：https://docs.flutter.dev/data-and-backend/state-mgmt/simple
- Android 官方 Storage Access Framework 文档：https://developer.android.com/training/data-storage/shared/documents-files

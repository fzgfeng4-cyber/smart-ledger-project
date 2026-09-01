# Mobile Architecture Agent 工作规则

## 1. 开始前必须读取

Mobile Architecture Agent 开始任何工作前，必须先读取：

- `PROJECT.md`
- `docs/android-v1-plan.md`
- `docs/product-v1.md`
- `docs/data-model.md`
- `docs/classification-rules.md`
- `docs/ui-plan.md`

可以参考：

- `frontend/`
- `backend/`

但 `frontend/` 和 `backend/` 只作为 Web Prototype 的业务参考。不得修改、覆盖、重构或让 Android APP V1 运行时依赖它们。

## 2. 当前职责

Mobile Architecture Agent 只负责：

“Android APP 内部代码应该如何组织，各模块如何通信，谁负责什么。”

本 Agent 的正式输出是：

- `docs/mobile-architecture.md`

本 Agent 不负责实现业务功能，不负责生成 APK，不负责创建正式 SQLite 数据库。

## 3. 必须遵守的 Android V1 架构

Android APP V1 架构已经冻结为：

- Flutter
- Dart
- APP 内部业务逻辑
- 手机本地 SQLite

Android APP V1 正常运行不依赖：

- FastAPI
- Python
- localhost
- 浏览器
- 外部 Backend

FastAPI `backend/` 只能作为 Web Prototype 和未来 API/云同步参考，不能成为 Android V1 的运行前提。

## 4. 架构设计原则

架构优先级：

1. 简单。
2. 新手能理解。
3. 模块职责清楚。
4. 容易测试。
5. 适合本地 SQLite。
6. 后续容易增加 V2/V3。
7. 不为了“专业”过度设计。

禁止为了架构漂亮引入：

- 微服务。
- Clean Architecture 多层过度拆分。
- 复杂依赖注入框架。
- Redux 级复杂状态管理。
- 不必要的代码生成。
- 大量抽象接口。
- 与 V1 无关的插件体系。

V1 是个人本地记账 APP。架构必须服务于“一句话输入 -> 解析 -> 用户确认/修改 -> 手机 SQLite 保存 -> 列表/统计/编辑/删除/备份”的闭环。

## 5. 必须复用的业务基线

架构设计必须复用既有 Web Prototype 的业务结论：

- Transaction 十字段：`id`、`amount_cents`、`type`、`category`、`note`、`original_text`、`transaction_date`、`created_at`、`updated_at`、`deleted_at`。
- 金额使用整数分，不使用浮点金额作为核心存储。
- `type` 只允许 `income` 和 `expense`。
- 分类使用稳定内部 code，不保存中文分类名作为主值。
- `original_text` 保留用户最初输入。
- 解析结果必须进入确认流程，不能直接写入 SQLite。
- 删除使用 `deleted_at` 软删除。
- 统计只统计未删除记录。
- 本地备份不等于导入、云同步或恢复中心。

不得因为改用 Flutter 而重新发明字段、分类、金额语义、日期语义、软删除语义或确认流程。

## 6. 本 Agent 必须解决的问题

`docs/mobile-architecture.md` 至少要回答：

1. `mobile/` 是否应通过标准 `flutter create` 生成，以及建议命令和停止点。
2. Flutter、Dart、Android SDK、minSdk、targetSdk 的基线选择原则。
3. Android APP V1 的推荐依赖类型，例如 SQLite、路径、文件保存、测试依赖；只说明原则，不锁定无依据版本。
4. 是否使用轻量状态管理方案，以及为什么不用复杂状态管理。
5. `mobile/lib/` 推荐目录结构。
6. domain、data、ui、shared 等模块的职责边界。
7. 解析器、校验器、repository、SQLite 数据源、页面状态之间如何通信。
8. 手机 SQLite 文件放置原则和备份能力在架构中的位置。
9. Android 最小权限原则如何落到 Manifest 和备份方案。
10. 后续 Mobile Data、Classification Migration、Flutter UI、Android Build、Mobile Test、Mobile Review 的文件所有权。
11. 哪些工作可以并行，哪些必须串行。
12. 架构完成后的验收标准和下一阶段入口。

如果需要检查本机 Flutter/Android 工具链状态，可以只做只读检查并记录“已验证/未验证”。不要因为工具链缺失而改写已冻结架构。

## 7. 禁止事项

本 Agent 不得：

- 正式实现 Flutter 页面。
- 创建完整业务代码。
- 创建真实 SQLite 数据库。
- 迁移完整分类解析代码。
- 构建 APK。
- 修改 `frontend/`。
- 修改 `backend/`。
- 修改 Web Prototype 的 API 契约来适配 Android。
- 增加微信、支付宝、淘宝、OCR、通知、短信、云同步、登录、多用户、复杂预算、高级图表或云端大模型依赖。
- 提前申请相机、相册、通知、短信、通讯录、后台服务、无障碍或读取其他 APP 数据权限。

如果发现必须改变产品范围、数据字段、分类 code 或运行架构，必须停止并报告主 Agent，不得自行扩展。

## 8. 输出要求

`docs/mobile-architecture.md` 必须使用简体中文，明确区分：

- 已确认采用的架构。
- 尚未验证的本机工具链状态。
- 后续 Agent 才能实现的内容。
- 当前阶段明确不做的内容。

报告中必须给出清晰的目录建议，但不能把建议目录等同于已经创建的文件。除非用户单独授权，本 Agent 不创建 `mobile/`。

## 9. 完成后必须汇报

Mobile Architecture Agent 完成后必须汇报：

- 读取了哪些文档。
- 写入了哪个文件。
- 推荐的 Flutter 架构和目录结构。
- 不使用 FastAPI/Python/localhost 的运行边界。
- 保留给后续 Agent 的文件所有权。
- 哪些内容仍需用户确认。

完成后停止，不进入 Mobile Data、Classification Migration、Flutter UI、Android Build、Mobile Test 或 Mobile Review 阶段。

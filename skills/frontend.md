# Frontend Agent 工作规则

## 1. 开始前必须读取

Frontend Agent 开始任何工作前，必须先读取：

- `PROJECT.md`
- `docs/product-v1.md`
- `docs/data-model.md`
- `docs/classification-rules.md`
- `docs/ui-plan.md`
- `docs/api-contract.md`

## 2. 职责范围

Frontend Agent 只主要负责：

- `frontend/`

Frontend Agent 负责：

- 前端页面
- 用户输入
- 调用 API
- 显示解析结果
- 用户修改确认
- 显示账单
- 编辑账目
- 删除账目
- 撤销删除
- 首页统计展示
- 普通中文错误提示

## 3. 技术栈

必须使用已经冻结的 V1 前端技术方向：

- Vue 3
- TypeScript
- Vite

不得擅自改用 React、原生 HTML/JavaScript、Nuxt、Next.js、Electron、Tauri 或其他技术路线。

## 4. API 契约

必须严格遵守 `docs/api-contract.md`。

禁止自己修改 API：

- 路径
- 参数
- 字段名称
- `category` code
- 错误格式

API 字段统一使用 `snake_case`，例如：

- `amount_cents`
- `transaction_date`
- `original_text`
- `created_at`
- `updated_at`
- `deleted_at`

不得在前端主数据模型中改成 `amountCents`、`transactionDate`、`money`、`price`、`date` 等另一套命名。

## 5. Frontend 不负责

Frontend Agent 不负责：

- SQLite
- 核心分类规则
- 自然语言解析实现
- 后端数据校验
- 数据库迁移
- SQLite 备份生成逻辑
- 真正的重复账目检测

这些职责属于 Backend Agent。

## 6. Mock 数据规则

后端尚未完成时，允许使用 mock 数据开发。

Mock 数据必须严格符合 `docs/api-contract.md`：

- API 路径要一致
- 请求字段要一致
- 响应字段要一致
- 错误格式要一致
- 分类 code 要一致
- 金额必须使用 `amount_cents` 的整数分
- 日期必须使用 `transaction_date` 的 `YYYY-MM-DD`

Mock 只能用于前端开发和演示，不能变成第二套真实数据存储。

## 7. V1 范围限制

不得增加 V1 之外的新功能，包括但不限于：

- 登录
- 注册
- 多用户
- 云同步
- 微信/支付宝授权
- 微信/支付宝账单导入
- OCR 上传
- 截图识别
- 通知采集
- AI 聊天
- 云端大模型配置
- 预算中心
- 年度报告
- 高级图表
- 社区
- 广告
- 多主题系统
- 复杂设置中心
- 一句话自动拆分多笔账

发现需要新增功能时，停止并报告主 Agent，不得自行扩展。

## 8. 响应式要求

必须实现手机和桌面基本响应式：

- 桌面端可正常完成首页、解析确认、账单列表、编辑、删除和备份入口操作。
- 手机端可正常输入、解析、修改五个确认字段、保存、查看列表、编辑、删除和撤销。
- 页面不能出现关键内容互相遮挡。
- 按钮、输入框和分类选项必须适合触屏点击。
- 不实现完整 PWA，不添加 Service Worker 或离线缓存系统。

## 9. 完成后必须汇报

Frontend Agent 完成后必须：

- 自己进行基本检查。
- 汇报修改了哪些文件。
- 汇报哪些功能已通过前端 mock 验证。
- 汇报还有哪些功能必须等待真实 Backend 才能验证。
- 停止，不进入 Backend、Test 或 Review 阶段。


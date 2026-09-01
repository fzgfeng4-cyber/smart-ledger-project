# Backend Agent 工作规则

## 1. 开始前必须读取

Backend Agent 开始任何工作前，必须先读取：

- `PROJECT.md`
- `docs/product-v1.md`
- `docs/technical-research.md`
- `docs/data-model.md`
- `docs/classification-rules.md`
- `docs/api-contract.md`

## 2. 职责范围

Backend Agent 只主要负责：

- `backend/`

Backend Agent 负责：

- 一句话解析
- 分类规则
- FastAPI 接口
- SQLite 数据库
- 数据验证
- 账目 CRUD
- 软删除
- 恢复
- 首页统计
- 简单重复提醒
- SQLite 备份

## 3. 技术栈

必须使用已经冻结的 V1 后端技术方向：

- Python
- FastAPI
- SQLite

不得擅自改用 Node.js、Express、Django、Flask、PostgreSQL、MySQL、云数据库或其他技术路线。

## 4. API 契约

必须严格遵守 `docs/api-contract.md`。

不能自己更改：

- API 路径
- 请求字段
- 返回字段
- HTTP 状态
- `category` code
- 统一错误格式

API 字段统一使用 `snake_case`，例如：

- `amount_cents`
- `transaction_date`
- `original_text`
- `created_at`
- `updated_at`
- `deleted_at`

如果发现接口契约不够用，必须停止并报告主 Agent，由主 Agent 决定是否修改 `docs/api-contract.md`。

## 5. 数据库规则

数据库必须遵守 `docs/data-model.md`。

核心要求：

- V1 使用一张 `transactions` 表。
- `amount_cents` 统一保存“分”的整数，必须大于 0。
- `type` 只允许 `income` 和 `expense`。
- `category` 必须使用已冻结的内部 code，并与 `type` 匹配。
- `transaction_date` 使用 `YYYY-MM-DD`。
- `original_text` 保存用户最初输入的原始字符串，普通编辑不覆盖。
- `created_at`、`updated_at`、`deleted_at` 使用时间戳。
- 删除使用 `deleted_at` 软删除。
- 首页统计只统计 `deleted_at IS NULL` 的记录。
- 数据库允许真实重复账目，重复提醒放在业务层。

## 6. Backend 不负责

Backend Agent 不负责：

- 前端页面
- UI 美化
- 前端状态管理
- V2/V3/V4 功能

不得增加：

- 登录注册
- 云同步
- OCR
- 微信/支付宝导入
- 银行同步
- 通知采集
- AI 大模型
- 高级预算
- 复杂报表
- 多用户系统

## 7. 实现边界

Backend Agent 实现时必须满足：

- `POST /api/parse` 只解析，不保存。
- 解析不完整返回正常业务响应，不返回 HTTP 500。
- 保存前必须校验金额、收支、分类、日期、未来日期、备注长度和 `original_text`。
- 未来日期可以解析，但不能保存。
- 负数金额不能自动取绝对值，不能自动翻转收入/支出。
- 多金额不能自动拆成两笔。
- 重复账目只提醒，不强制禁止保存。
- 删除是软删除，不是物理删除。
- 撤销删除恢复同一条记录。
- SQLite 备份必须使用安全备份机制，不能把正在写入的数据库文件直接复制当作一致性保证。

## 8. 安全和本地运行

Backend Agent 必须遵守：

- 默认只监听本机回环地址 `127.0.0.1`。
- 开发期 CORS 只允许明确的本地前端地址。
- SQL 必须使用参数绑定，不拼接用户输入。
- 错误响应不得暴露 Python traceback、SQLite exception、SQL 语句或本机敏感路径。
- 不需要账号、密码、Token、API Key 或云端配置。

## 9. 完成后必须汇报

Backend Agent 完成后必须：

- 运行自动测试。
- 进行语法检查。
- 汇报修改了哪些文件。
- 汇报 API 实测情况。
- 汇报哪些接口已完成，哪些仍需联调。
- 停止，不进入 Frontend、Test 或 Review 阶段。


# Smart Ledger V1 API 接口契约

## 文档定位

- 状态：V1 前后端接口正式契约，主 Agent 总方案冻结产物。
- 读取对象：Frontend Agent、Backend Agent、Test Agent、Review Agent、主 Agent。
- 依据：`PROJECT.md`、`docs/product-v1.md`、`docs/technical-research.md`、`docs/data-model.md`、`docs/classification-rules.md`、`docs/ui-plan.md`。
- 范围：只定义 API 路径、请求字段、响应字段、错误格式、HTTP 状态码、前后端职责和开发顺序。
- 本文不创建 `frontend/`、`backend/`、SQLite 数据库，也不写业务代码。

V1 接口只服务本地单用户 Web App。路径保持简单，统一放在 `/api` 下；后续如果变成公开 API 或多版本外部接口，再单独评估 `/api/v1` 版本前缀。

## 1. 总方案一致性检查

| 检查项 | 结论 |
| --- | --- |
| Product 要求的功能，UI 是否都有入口 | 通过。首页有快速记账、统计、最近账目；账单列表可查看全部；账目工作页支持确认、编辑、删除；右上角菜单有备份入口。 |
| UI 允许修改的字段，Data Model 是否都支持 | 通过。金额、收入/支出、分类、备注、日期分别对应 `amount_cents`、`type`、`category`、`note`、`transaction_date`。 |
| Classification 输出字段，Data Model 是否全部存在 | 通过。`amount_cents`、`type`、`category`、`note`、`original_text`、`transaction_date` 都已在 Transaction 中冻结。 |
| Classification 的 category code 是否统一 | 通过。前端和后端都使用同一套固定 code，前端只把 code 映射成中文显示。 |
| `amount_cents` 是否统一使用分的整数 | 通过。API、后端、SQLite 都用整数分；前端只在显示和输入时转换成人民币元。 |
| `transaction_date` 是否统一使用 `YYYY-MM-DD` | 通过。接口请求、响应和数据库都使用 `YYYY-MM-DD`。 |
| `original_text` 是否全过程原样保持 | 通过。解析保存原始输入；新增保存该原文；普通编辑不修改它；列表不重复展示。 |
| `type` 是否只使用 `income` / `expense` | 通过。接口、分类和数据校验只允许这两个值。 |
| `deleted_at` 软删除是否和 UI 删除/撤销一致 | 通过。删除接口设置 `deleted_at`，列表和统计默认排除；撤销接口恢复同一条记录。 |
| 未来日期规则是否一致 | 通过。可以解析，但保存前必须提示 `这个日期在未来，请检查日期。`，并禁止保存。 |
| 重复账目规则是否一致 | 通过。只提醒，不设置唯一约束，不强制阻止真实重复交易。 |
| V1 禁止功能是否仍未进入方案 | 通过。不包含微信/支付宝导入、OCR、通知采集、云同步、登录注册、AI 大模型和复杂图表。 |

当前没有阻塞 V1 冻结的冲突。Research 阶段早期留下的待决问题已由后续主 Agent 检查点和本文关闭；后续实现以 `PROJECT.md` 与本文为最终接口依据。

## 2. 全局 API 规则

### 2.1 基础约定

- 本地服务地址：开发和自用时使用 `http://127.0.0.1:<port>`。
- API 前缀：`/api`。
- 请求格式：除备份下载外，默认 `Content-Type: application/json; charset=utf-8`。
- 响应格式：除备份下载外，默认 JSON。
- 字段命名：统一 `snake_case`。
- 金额：统一使用 `amount_cents`，单位为分，类型为整数。
- 账务日期：统一使用 `transaction_date`，格式为 `YYYY-MM-DD`。
- 时间戳：`created_at`、`updated_at`、`deleted_at` 使用 UTC ISO 8601 字符串，例如 `2026-08-30T08:30:00Z`。
- 用户输入：`original_text` 必须保存用户提交并用于生成确认页的原始字符串，不使用清理后的解析副本覆盖。

### 2.2 成功响应形状

V1 不使用复杂的统一 `data` 信封。单个资源直接返回对象；列表返回 `items` 和必要分页信息；解析接口返回 `draft` 加解析状态；备份接口返回文件下载。

### 2.3 错误响应形状

所有接口的错误响应统一为：

```json
{
  "error": {
    "code": "VALIDATION_ERROR",
    "message": "金额必须大于 0",
    "details": [
      {
        "field": "amount_cents",
        "message": "金额必须大于 0"
      }
    ]
  }
}
```

`details` 可省略。前端默认展示 `error.message`；需要定位具体字段时再使用 `details`。不得把 Python traceback、SQLite exception、HTTP stack trace 或内部 SQL 暴露给用户。

### 2.4 HTTP 状态码

| 状态码 | 使用场景 |
| --- | --- |
| `200` | 查询成功、解析成功或解析出待处理草稿、修改成功、软删除成功、撤销成功、重复提醒返回。 |
| `201` | 新建账目真正保存成功。 |
| `400` | 请求 JSON 格式错误、字段缺失、字段类型错误、金额非法、分类不合法、未来日期提交保存等用户请求错误。 |
| `404` | 指定账目不存在，或对普通查询/编辑/删除来说已经是不可见的已删除账目。 |
| `409` | 状态冲突，例如撤销窗口已过、账目并非已删除却请求恢复。重复账目提醒不使用 `409`。 |
| `500` | 后端内部错误。响应只给普通中文提示，不暴露技术细节。 |

“解析结果不完整”不是 HTTP 错误。例如输入“买菜”没有金额，应返回 `200` 和 `status = "needs_input"`，让前端正常显示补充界面。

## 3. 共享数据结构

### 3.1 Transaction

已保存账目的响应对象：

```json
{
  "id": 1,
  "amount_cents": 3500,
  "type": "expense",
  "category": "groceries_food",
  "note": "买菜",
  "original_text": "昨天35块买菜",
  "transaction_date": "2026-08-29",
  "created_at": "2026-08-30T08:30:00Z",
  "updated_at": "2026-08-30T08:30:00Z",
  "deleted_at": null
}
```

`deleted_at` 通常为 `null`，普通列表和统计不返回已删除记录。支出金额仍然是正整数分，不能用负数表示支出。

### 3.2 TransactionDraft

解析接口返回的待确认草稿：

```json
{
  "amount_cents": 3500,
  "type": "expense",
  "category": "groceries_food",
  "note": "买菜",
  "original_text": "昨天35块买菜",
  "transaction_date": "2026-08-29"
}
```

草稿字段允许为 `null`，表示需要用户补充或修改。草稿不是数据库记录，没有 `id`、`created_at`、`updated_at`、`deleted_at`。

### 3.3 Category

```json
{
  "code": "groceries_food",
  "name": "买菜/食品",
  "type": "expense"
}
```

`code` 是保存和提交给后端的值；`name` 只用于显示；`type` 决定它属于收入还是支出。

### 3.4 ParseWarning

```json
{
  "code": "MISSING_AMOUNT",
  "field": "amount_cents",
  "message": "缺少金额",
  "candidates": []
}
```

- `code`：机器可判断的提示类型。
- `field`：相关字段；若是整句问题可为 `null`。
- `message`：前端可以直接显示给用户的中文。
- `candidates`：候选值，通常用于分类冲突，例如 `["dining", "children"]`；没有候选时为空数组。

### 3.5 V1 分类 code

| type | code | 中文名 |
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

前端不得自行创建额外 code；后端必须校验分类 code 与 `type` 匹配。

## 4. API 清单

| 方法 | 路径 | 用途 |
| --- | --- | --- |
| `POST` | `/api/parse` | 把一句自然语言解析成待确认草稿，只解析，不保存。 |
| `GET` | `/api/categories` | 返回 V1 固定分类目录。 |
| `POST` | `/api/transactions` | 保存用户确认后的新账目。 |
| `GET` | `/api/transactions` | 获取未删除账目列表。 |
| `GET` | `/api/transactions/{id}` | 获取单笔未删除账目详情。 |
| `PUT` | `/api/transactions/{id}` | 修改一笔已保存账目的五个可编辑字段。 |
| `DELETE` | `/api/transactions/{id}` | 软删除一笔账，设置 `deleted_at`。 |
| `POST` | `/api/transactions/{id}/restore` | 在撤销窗口内恢复软删除账目。 |
| `GET` | `/api/summary` | 获取首页三个基础统计。 |
| `GET` | `/api/backup` | 下载当前 SQLite 数据库备份文件。 |

## 5. POST /api/parse

### 5.1 用途

前端把用户输入的原始文字交给后端，后端用规则、关键词和正则解析成待确认草稿。该接口绝对不能自动保存账目，也不能写入 SQLite。

### 5.2 请求

```json
{
  "text": "昨天35块买菜"
}
```

规则：

- `text` 必须是字符串。
- 空字符串或全空白字符串返回 `200` 和 `status = "no_draft"`。
- 文本超过 `original_text` 上限时返回 `400`，错误码 `VALIDATION_ERROR`。
- 后端必须用原始 `text` 填入 `draft.original_text`，不能用清理后的解析副本覆盖。

### 5.3 响应

```json
{
  "status": "ready",
  "needs_confirmation": false,
  "draft": {
    "amount_cents": 3500,
    "type": "expense",
    "category": "groceries_food",
    "note": "买菜",
    "original_text": "昨天35块买菜",
    "transaction_date": "2026-08-29"
  },
  "missing_fields": [],
  "warnings": []
}
```

`status` 只能是：

| status | 含义 | 前端行为 |
| --- | --- | --- |
| `ready` | 字段完整且无明显不确定 | 展示确认区，用户点击“确认记账”后再调用保存接口。 |
| `needs_confirmation` | 字段有建议，但存在兜底分类、裸数字、分类冲突等需要用户明确确认的点 | 展示确认区，高亮对应字段；用户处理提示前不启用保存。 |
| `needs_input` | 缺少金额、方向、分类、日期，或金额/日期非法、多金额等 | 展示补充状态；用户补齐或改写前不启用保存。 |
| `no_draft` | 空输入或完全无记账意义 | 停留输入状态，不进入正常确认页。 |

`needs_confirmation` 是给前端判断“是否有必须处理的提示”的布尔值。无论它是 `true` 还是 `false`，解析结果都只是建议，用户没有点击确认前都不能保存。

### 5.4 缺金额示例

输入“买菜”返回 `200`：

```json
{
  "status": "needs_input",
  "needs_confirmation": true,
  "draft": {
    "amount_cents": null,
    "type": "expense",
    "category": "groceries_food",
    "note": "买菜",
    "original_text": "买菜",
    "transaction_date": "2026-08-30"
  },
  "missing_fields": ["amount_cents"],
  "warnings": [
    {
      "code": "MISSING_AMOUNT",
      "field": "amount_cents",
      "message": "缺少金额",
      "candidates": []
    }
  ]
}
```

### 5.5 多金额示例

输入“买菜35又打车20”返回 `200`：

```json
{
  "status": "needs_input",
  "needs_confirmation": true,
  "draft": {
    "amount_cents": null,
    "type": "expense",
    "category": null,
    "note": "买菜又打车",
    "original_text": "买菜35又打车20",
    "transaction_date": "2026-08-30"
  },
  "missing_fields": ["amount_cents", "category"],
  "warnings": [
    {
      "code": "MULTIPLE_AMOUNTS",
      "field": "amount_cents",
      "message": "识别到多个金额，一次只能记一笔账，请拆成两笔记录。",
      "candidates": []
    },
    {
      "code": "CATEGORY_AMBIGUOUS",
      "field": "category",
      "message": "这句话可能包含多个事项，请选择一笔账对应的分类。",
      "candidates": ["groceries_food", "transportation"]
    }
  ]
}
```

### 5.6 未来日期示例

输入“12月20日买菜35”且该日期晚于当前本机日期时返回 `200`：

```json
{
  "status": "needs_input",
  "needs_confirmation": true,
  "draft": {
    "amount_cents": 3500,
    "type": "expense",
    "category": "groceries_food",
    "note": "买菜",
    "original_text": "12月20日买菜35",
    "transaction_date": "2026-12-20"
  },
  "missing_fields": [],
  "warnings": [
    {
      "code": "FUTURE_DATE",
      "field": "transaction_date",
      "message": "这个日期在未来，请检查日期。",
      "candidates": []
    }
  ]
}
```

未来日期可以作为候选展示，但在用户改成今天或过去日期前，不能提交到保存接口。

## 6. GET /api/categories

### 6.1 用途

返回后端掌握的 V1 固定分类目录，避免前端和后端各维护一套容易不一致的分类表。

### 6.2 响应

```json
{
  "items": [
    {
      "code": "dining",
      "name": "餐饮",
      "type": "expense"
    },
    {
      "code": "groceries_food",
      "name": "买菜/食品",
      "type": "expense"
    },
    {
      "code": "salary",
      "name": "工资",
      "type": "income"
    }
  ]
}
```

实际响应必须包含第 3.5 节的全部 13 个分类。前端可按 `type` 分组展示；不能把中文 `name` 当作保存值。

## 7. POST /api/transactions

### 7.1 用途

保存用户已经确认后的新账目。这个接口接收结构化字段，不接收一句自然语言直接落库。前端必须先让用户看到并确认字段，再调用本接口。

### 7.2 请求

```json
{
  "amount_cents": 3500,
  "type": "expense",
  "category": "groceries_food",
  "note": "买菜",
  "original_text": "昨天35块买菜",
  "transaction_date": "2026-08-29",
  "confirm_duplicate": false
}
```

字段规则：

| 字段 | 是否必填 | 说明 |
| --- | --- | --- |
| `amount_cents` | 是 | 正整数分，必须大于 0。 |
| `type` | 是 | 只能是 `expense` 或 `income`。 |
| `category` | 是 | 必须是固定分类 code，且与 `type` 匹配。 |
| `note` | 否 | 字符串或 `null`；空白归一为 `null`；最长 200 字符。 |
| `original_text` | 是 | 用户最初输入并用于确认的原始字符串；最长 500 字符；不得为空白。 |
| `transaction_date` | 是 | `YYYY-MM-DD`，真实有效日期，不能是未来日期。 |
| `confirm_duplicate` | 否 | 默认 `false`；只用于用户确认重复提醒，不写入数据库。 |

后端必须重复校验这些字段。前端校验只能提升体验，不能替代后端校验。

### 7.3 保存成功响应

无重复提醒或用户已经传入 `confirm_duplicate = true` 时，保存成功返回 `201`：

```json
{
  "transaction": {
    "id": 1,
    "amount_cents": 3500,
    "type": "expense",
    "category": "groceries_food",
    "note": "买菜",
    "original_text": "昨天35块买菜",
    "transaction_date": "2026-08-29",
    "created_at": "2026-08-30T08:30:00Z",
    "updated_at": "2026-08-30T08:30:00Z",
    "deleted_at": null
  },
  "duplicate_warning": false,
  "similar_transaction": null
}
```

### 7.4 重复提醒响应

V1 的重复提醒采用最简单方案：后端只检查最近约 10 分钟内保存的最后一笔未删除账目，若 `transaction_date + amount_cents + type + category + note` 完全相同，则先不保存，返回 `200`：

```json
{
  "transaction": null,
  "duplicate_warning": true,
  "similar_transaction": {
    "id": 1,
    "amount_cents": 3500,
    "type": "expense",
    "category": "groceries_food",
    "note": "买菜",
    "original_text": "昨天35块买菜",
    "transaction_date": "2026-08-29",
    "created_at": "2026-08-30T08:30:00Z",
    "updated_at": "2026-08-30T08:30:00Z",
    "deleted_at": null
  },
  "message": "刚刚似乎记过一笔 ¥35.00 买菜"
}
```

用户点击“仍然记账”后，前端用相同字段再次调用本接口，并设置 `confirm_duplicate = true`。后端此时应保存并返回 `201`。重复提醒不使用数据库唯一约束，不扫描所有历史账，不合并、不覆盖、不删除真实重复记录。

### 7.5 常见错误

- `400 VALIDATION_ERROR`：金额小于等于 0、字段缺失、分类与 `type` 不匹配、未来日期、备注过长、原始输入为空或过长。
- `500 INTERNAL_ERROR`：数据库写入等后端内部失败，但不得暴露内部细节。

## 8. GET /api/transactions

### 8.1 用途

返回账单列表需要的未删除账目。V1 不做复杂筛选、搜索、分类过滤、报表或批量操作。

### 8.2 查询参数

| 参数 | 默认值 | 规则 |
| --- | --- | --- |
| `page` | `1` | 正整数，从 1 开始。 |
| `page_size` | `50` | 正整数，建议最大 100。 |

V1 采用简单分页，方便长期自用后账目变多。排序固定为：`transaction_date` 从新到旧，同一天内 `updated_at` 从新到旧，再用 `id` 兜底。

### 8.3 响应

```json
{
  "items": [
    {
      "id": 1,
      "amount_cents": 3500,
      "type": "expense",
      "category": "groceries_food",
      "note": "买菜",
      "original_text": "昨天35块买菜",
      "transaction_date": "2026-08-29",
      "created_at": "2026-08-30T08:30:00Z",
      "updated_at": "2026-08-30T08:30:00Z",
      "deleted_at": null
    }
  ],
  "page": 1,
  "page_size": 50,
  "total": 1,
  "has_next": false
}
```

普通列表不返回 `deleted_at` 非空记录。前端列表不展示 `original_text`，但接口保留完整 Transaction，便于点击行进入编辑页。

## 9. GET /api/transactions/{id}

### 9.1 用途

返回单笔未删除账目详情，用于账目工作页查看和编辑。

### 9.2 响应

成功返回 `200` 和一个 Transaction 对象：

```json
{
  "id": 1,
  "amount_cents": 3500,
  "type": "expense",
  "category": "groceries_food",
  "note": "买菜",
  "original_text": "昨天35块买菜",
  "transaction_date": "2026-08-29",
  "created_at": "2026-08-30T08:30:00Z",
  "updated_at": "2026-08-30T08:30:00Z",
  "deleted_at": null
}
```

如果账目不存在或已经软删除，对普通详情读取返回 `404 NOT_FOUND`。

## 10. PUT /api/transactions/{id}

### 10.1 用途

修改一笔已保存账目的五个可编辑字段。V1 选择 `PUT`，因为编辑页总是提交完整的五个业务字段；这比 `PATCH` 更适合新手理解和测试。

### 10.2 请求

```json
{
  "amount_cents": 3580,
  "type": "expense",
  "category": "groceries_food",
  "note": "买菜和水果",
  "transaction_date": "2026-08-29"
}
```

规则：

- 只允许提交 `amount_cents`、`type`、`category`、`note`、`transaction_date`。
- 不允许提交或覆盖 `original_text`、`id`、`created_at`、`updated_at`、`deleted_at`。
- `created_at` 保持不变。
- `original_text` 保持最初输入，不随普通编辑变化。
- 保存成功后更新 `updated_at`。
- 未来日期仍然禁止保存。

### 10.3 响应

成功返回 `200` 和更新后的 Transaction：

```json
{
  "id": 1,
  "amount_cents": 3580,
  "type": "expense",
  "category": "groceries_food",
  "note": "买菜和水果",
  "original_text": "昨天35块买菜",
  "transaction_date": "2026-08-29",
  "created_at": "2026-08-30T08:30:00Z",
  "updated_at": "2026-08-30T08:35:00Z",
  "deleted_at": null
}
```

常见错误：`400 VALIDATION_ERROR`、`404 NOT_FOUND`、`500 INTERNAL_ERROR`。

## 11. DELETE /api/transactions/{id}

### 11.1 用途

删除一笔账目，但实际执行软删除：设置 `deleted_at`，不物理删除 SQLite 记录。

### 11.2 响应

成功返回 `200`：

```json
{
  "deleted": true,
  "id": 1,
  "deleted_at": "2026-08-30T08:40:00Z",
  "restore_available_until": "2026-08-30T08:40:10Z",
  "restore_url": "/api/transactions/1/restore",
  "message": "已删除这笔账"
}
```

前端收到成功后立即从页面隐藏该账目，刷新统计，并显示 `已删除这笔账   撤销` 约 10 秒。

如果账目不存在或已删除，返回 `404 NOT_FOUND`。

## 12. POST /api/transactions/{id}/restore

### 12.1 用途

恢复刚刚软删除的账目，把 `deleted_at` 恢复为 `null`，并更新 `updated_at`。V1 不做垃圾桶页面，也不做删除记录管理中心。

### 12.2 响应

10 秒撤销窗口内成功恢复，返回 `200`：

```json
{
  "restored": true,
  "transaction": {
    "id": 1,
    "amount_cents": 3500,
    "type": "expense",
    "category": "groceries_food",
    "note": "买菜",
    "original_text": "昨天35块买菜",
    "transaction_date": "2026-08-29",
    "created_at": "2026-08-30T08:30:00Z",
    "updated_at": "2026-08-30T08:40:05Z",
    "deleted_at": null
  }
}
```

错误：

- `404 NOT_FOUND`：账目不存在。
- `409 RESTORE_WINDOW_EXPIRED`：撤销窗口已过。
- `409 NOT_DELETED`：账目当前不是已删除状态。

后端不需要因为 10 秒窗口结束就物理清理记录；只是不再允许这个 V1 撤销入口恢复它。

## 13. GET /api/summary

### 13.1 用途

返回首页三个基础统计。V1 不返回图表、趋势、分类占比、余额、预算或年度报告。

### 13.2 响应

```json
{
  "today_expense_cents": 3500,
  "month_expense_cents": 235680,
  "month_income_cents": 800000
}
```

统计规则：

- 只统计 `deleted_at IS NULL` 的有效账目。
- 今天支出：`transaction_date` 等于当前本机日期，且 `type = "expense"`。
- 本月支出：`transaction_date` 位于当前本机月份，且 `type = "expense"`。
- 本月收入：`transaction_date` 位于当前本机月份，且 `type = "income"`。
- 金额合计使用整数分；前端展示时再格式化为人民币。

## 14. GET /api/backup

### 14.1 用途

手动下载当前 SQLite 数据库备份文件。V1 只做本地备份下载，不做云备份、自动同步、导入恢复、多版本管理或恢复中心。

### 14.2 响应

成功返回 `200` 和文件流：

```text
Content-Type: application/vnd.sqlite3
Content-Disposition: attachment; filename="smart-ledger-backup-20260830-083000.sqlite"
```

备份文件名格式：

```text
smart-ledger-backup-YYYYMMDD-HHMMSS.sqlite
```

后端必须使用 SQLite 安全备份机制生成备份，不能把正在写入的数据库文件直接复制当作一致性保证。

失败时返回统一错误格式，例如：

```json
{
  "error": {
    "code": "BACKUP_FAILED",
    "message": "备份暂时失败，请稍后重试"
  }
}
```

## 15. V1 错误 code

V1 只定义少量必要错误码，后续不要为了“完整”创建几十个错误码。

| code | 建议 HTTP 状态 | 含义 |
| --- | --- | --- |
| `INVALID_REQUEST` | 400 | JSON 无法解析、请求体不是对象、参数类型明显错误。 |
| `VALIDATION_ERROR` | 400 | 字段校验失败，例如金额、分类、日期、长度不合法。 |
| `NOT_FOUND` | 404 | 账目不存在，或普通读取/编辑/删除时目标不可见。 |
| `RESTORE_WINDOW_EXPIRED` | 409 | 删除后的约 10 秒撤销窗口已过。 |
| `NOT_DELETED` | 409 | 请求恢复的账目当前不是已删除状态。 |
| `BACKUP_FAILED` | 500 | 备份生成失败。 |
| `INTERNAL_ERROR` | 500 | 未预期的后端内部错误。 |

解析过程的 `MISSING_AMOUNT`、`MULTIPLE_AMOUNTS`、`FUTURE_DATE` 等放在 `warnings[].code` 中，不作为 HTTP 错误码。

## 16. 前后端职责边界

### 16.1 Frontend Agent 负责

- 页面结构和用户交互。
- 用户输入与 Enter/按钮触发解析。
- 调用本文 API。
- 显示解析结果和不确定字段。
- 让用户修改金额、收入/支出、分类、备注、日期。
- 调用新增、列表、详情、修改、删除、撤销、统计、备份接口。
- 用普通中文展示错误提示。
- 使用 mock 数据按本文接口形状先开发页面。

Frontend Agent 不负责：

- SQLite 文件和数据库读写。
- 分类核心规则和自然语言解析。
- 数据库约束与最终校验。
- 真正的重复检测。
- 云端 AI、导入、OCR、通知采集、登录注册或同步。

### 16.2 Backend Agent 负责

- FastAPI 路由与统一错误格式。
- 规则、关键词和正则解析。
- 分类目录统一来源。
- SQLite 数据库创建、迁移和参数化读写。
- 保存前字段校验。
- 账目新增、列表、详情、修改、软删除、恢复。
- 首页统计。
- 重复提醒。
- SQLite 安全备份下载。
- 默认只监听本机回环地址，开发期 CORS 只允许明确本地来源。

Backend Agent 不负责：

- 页面布局和视觉细节。
- 前端状态管理。
- 直接实现 V2/V3/V4 功能。
- 账号、云同步、外部支付平台、OCR 或 AI 大模型接入。

## 17. 项目目录边界

后续正式开发时采用以下目录边界：

| 目录 | 主要负责人 | 说明 |
| --- | --- | --- |
| `frontend/` | Frontend Agent | Vue 3 + TypeScript + Vite 前端页面、状态和 API 调用。 |
| `backend/` | Backend Agent | Python + FastAPI + SQLite 后端、解析、校验、CRUD、统计、备份。 |
| `docs/` | 主 Agent 和对应文档 Agent | 项目规划、需求、数据模型、分类规则、UI 方案、API 契约和后续报告。 |
| `skills/` | 主 Agent | 各开发 Agent 的工作规则。 |
| `tests/` | Test Agent 为主，主 Agent 协调 | 后续测试文件和测试报告；具体结构在测试阶段确定。 |

原则：Frontend Agent 和 Backend Agent 不应随意同时修改同一个文件。共享字段、路径和错误格式以本文为准；如果实现中发现契约不够，应回到主 Agent 修改本文后再继续。

## 18. API 契约后的开发顺序

采用前后端并行开发，但必须以本文为共同契约：

1. 主 Agent 先创建 `skills/backend.md` 和 `skills/frontend.md`，明确两个开发 Agent 的文件边界和禁止事项。
2. Backend Agent 创建 `backend/`，按本文实现真实 API、SQLite、解析规则、校验、统计、备份。
3. Frontend Agent 创建 `frontend/`，先用固定 mock 数据和本文接口形状实现页面、状态和交互。
4. 两边分别完成后，主 Agent 做联调：把前端 mock 切换为真实 API，检查字段、状态码、错误格式和 UX 行为。
5. 再派 Test Agent 创建测试方案和测试代码，覆盖解析、CRUD、统计、删除撤销、重复提醒和 UI 关键流程。
6. 最后派 Review Agent 做范围、数据安全、契约一致性和 V1 停止线审查。

可以并行的工作：

- Frontend Agent 的页面与 mock API。
- Backend Agent 的真实 API 与 SQLite。
- 主 Agent 的联调清单整理。

必须先后的工作：

- API 契约必须先于 Frontend/Backend 实现。
- 后端数据模型和分类规则必须先于真实保存接口。
- 前端 mock 必须按本文字段写，不能自己发明字段。
- 联调必须在前后端各自最小闭环完成后进行。
- Test 和 Review 必须在有可运行实现后进行。

## 19. V1 冻结声明

从本文完成开始，V1 需求和接口正式冻结：

- V1 只做一句话智能记账。
- V1 是普通本地 Web App。
- V1 使用 Vue 3 + TypeScript + Vite、Python + FastAPI、SQLite。
- V1 使用规则、关键词和正则解析，不接入云端大模型。
- V1 所有金额内部使用整数分。
- V1 保存前必须用户确认。
- V1 只保存 `transactions` 一张核心表。
- V1 不做微信/支付宝导入、OCR、通知采集、云同步、登录注册、多用户、AI 聊天、复杂图表、预算系统或社交功能。

任何 Agent 如果认为需要改变字段、路径、状态码、分类、页面数量或 V1 范围，必须停止并回报主 Agent，不得直接在实现中扩展。

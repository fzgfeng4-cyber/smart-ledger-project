# Smart Ledger V1 数据模型

## 文档定位

- 本文是 Data Agent 的 V1 数据设计契约，定义“已保存的一笔账”如何在用户界面、前端、后端 API 和 SQLite 中表示。
- 本文只做数据设计，不创建真实数据库，不创建 `frontend/` 或 `backend/`，不实现解析、业务接口或页面。
- 本文依据 `PROJECT.md`、`docs/product-v1.md`、`docs/technical-research.md` 和 `skills/data.md`。
- 识别结果是待确认草稿；只有用户确认后写入 `transactions` 的记录才是正式账目。

## 1. 最终结论

| 问题 | V1 决定 |
| --- | --- |
| 核心表 | 只需要一张 `transactions` 表；删除状态也放在这张表中。 |
| 最终字段 | `id`、`amount_cents`、`type`、`category`、`note`、`original_text`、`transaction_date`、`created_at`、`updated_at`、`deleted_at`。 |
| 金额 | `amount_cents` 使用 SQLite `INTEGER` 保存“分”，必须大于 0；收入和支出不使用金额正负表示。 |
| 收支 | `type` 只能是 `expense` 或 `income`。 |
| 分类 | `category` 保存稳定的内部 code，界面再映射为中文名称；V1 不建立分类表。 |
| 日期 | `transaction_date` 保存本机账务日期，格式为 `YYYY-MM-DD`，不保存时分秒。 |
| 时间戳 | `created_at` 和 `updated_at` 保存 UTC ISO 8601 时间字符串；它们不是账务日期。 |
| 备注 | `note` 可空，保存为 `NULL` 或最多 200 个字符的文本；空白备注归一为 `NULL`。 |
| 原始输入 | `original_text` 保存用户最初输入的原句，用于追溯识别结果和后续规则优化；不作为账单列表核心展示字段。 |
| 删除 | 使用 `deleted_at` 做软删除，默认列表、统计和重复提醒只看 `deleted_at IS NULL` 的记录。 |
| 重复账 | 数据库不禁止重复；重复提醒属于后端/API 与前端确认流程，用户仍可以保存真实的重复消费。 |
| 备份 | `smart-ledger.sqlite` 是完整账目数据库；备份使用 SQLite 安全备份机制生成完整 `.sqlite` 文件。 |

## 2. 一套统一命名

同一个概念只使用一个字段名。用户看到的是中文标签，前端 TypeScript、后端 API 和 SQLite 都使用下表中的英文 snake_case 名称。前端不得再维护一套不同含义的 `amount`、`amountYuan`、`categoryName` 等主字段。

| 用户看到的概念 | API/前端字段 | SQLite 列 | 值的形式 |
| --- | --- | --- | --- |
| 金额 | `amount_cents` | `amount_cents` | 正整数分；展示时格式化为人民币金额。 |
| 收入/支出 | `type` | `type` | `expense` 或 `income`；展示为“支出”或“收入”。 |
| 分类 | `category` | `category` | 稳定内部 code；展示为对应中文名称。 |
| 备注 | `note` | `note` | 字符串或 `null`；不使用另一个“描述”字段。 |
| 原始输入 | `original_text` | `original_text` | 用户最初输入的一句话；作为追溯字段保存，不等同于备注。 |
| 账务日期 | `transaction_date` | `transaction_date` | `YYYY-MM-DD` 字符串。 |
| 记录编号 | `id` | `id` | SQLite 生成的整数标识。 |
| 创建时间 | `created_at` | `created_at` | UTC ISO 8601 时间字符串。 |
| 最后修改时间 | `updated_at` | `updated_at` | UTC ISO 8601 时间字符串。 |
| 删除时间 | `deleted_at` | `deleted_at` | 未删除为 `null`，已删除为 UTC ISO 8601 时间字符串。 |

API 的金额真相是 `amount_cents`，不另外传一个可能产生精度差异的浮点 `amount`。API 的分类真相是 `category` code，不把当前中文名称复制成 `category_name` 存回账目。中文名称由前端或后端返回的固定分类映射展示，但不能替代保存的 code。

一个已保存账目的 API 形状可理解为以下示意对象；这不是业务实现代码，也不要求本轮创建接口：

```json
{
  "id": 1,
  "amount_cents": 3500,
  "type": "expense",
  "category": "groceries_food",
  "note": "买菜",
  "original_text": "35块买菜",
  "transaction_date": "2026-08-29",
  "created_at": "2026-08-29T08:30:00Z",
  "updated_at": "2026-08-29T08:30:00Z",
  "deleted_at": null
}
```

`deleted_at` 是后端状态字段，前端可以不向普通用户展示；它仍属于统一数据契约，不能被前端自行改写为另一个删除标记。

## 3. Transaction 账目模型

### 3.1 字段定义

| 字段 | SQLite 类型 | 是否可空 | 用户是否编辑 | V1 规则 |
| --- | --- | --- | --- | --- |
| `id` | `INTEGER PRIMARY KEY` | 否 | 否 | 数据库生成的稳定记录标识。它只用于定位一笔账，不代表金额、顺序或用户数量。 |
| `amount_cents` | `INTEGER` | 否 | 是 | 以分保存的正整数；不能是 0 或负数。 |
| `type` | `TEXT` | 否 | 是 | 只能是 `expense` 或 `income`。 |
| `category` | `TEXT` | 否 | 是 | 只能使用本文件规定的 V1 category code，并且要与 `type` 的收支方向匹配。 |
| `note` | `TEXT` | 是 | 是 | 可为空；去除首尾空白后保存，最长 200 个字符。 |
| `original_text` | `TEXT` | 否 | 否 | 保存用户最初输入的一句话原文；不得用清理后的解析副本覆盖，最长 500 个字符。 |
| `transaction_date` | `TEXT` | 否 | 是 | 最终账务日期，严格使用 `YYYY-MM-DD`；允许有效历史日期，不允许未来日期。 |
| `created_at` | `TEXT` | 否 | 否 | 首次保存时间；创建后保持不变。 |
| `updated_at` | `TEXT` | 否 | 否 | 最近一次新增、编辑、删除或恢复操作的时间。 |
| `deleted_at` | `TEXT` | 是 | 否 | `NULL` 表示有效；非 `NULL` 表示已软删除。普通用户不直接编辑此字段。 |

用户可编辑的五个业务字段是 `amount_cents` 对应的金额、`type`、`category`、`note` 和 `transaction_date`。`original_text` 是追溯字段，来自用户最初输入的一句话，保存后普通编辑不修改它。`id`、三个时间字段是系统字段，不增加新的业务概念。

### 3.2 不提前加入的字段

以下字段不属于 V1 的 Transaction：

- `merchant`：V1 不要求独立识别、筛选或统计商户；原句中的商户文字可暂时落在用户可编辑的 `note` 中。
- `source`：V1 只有本地手工输入这一种进入方式，不区分现金、银行卡、微信、支付宝或其他来源。
- `external_transaction_id`：V1 没有外部平台记录，当前没有可保持的外部唯一编号。
- 用户、账户、支付方式、预算、同步、OCR、导入任务、权限和 AI 置信度字段：都超出 V1。

不预留空字段可以避免后续 Agent 把尚未定义的概念误当成当前功能。`original_text` 已经作为 V1 核心追溯字段正式加入，但它不代表商户、来源、导入、OCR 或 AI 功能。未来需要其他概念时通过正式迁移加入，并同步更新 API 和测试契约。

## 4. 金额设计

### 4.1 正式决定

数据库字段使用 `amount_cents`，SQLite 类型使用 `INTEGER`。例如 35 元保存为 `3500`，35.80 元保存为 `3580`，300 元保存为 `30000`。

金额本身始终保存为正整数分：

- `amount_cents > 0` 才能保存。
- `amount_cents = 0` 不代表“没有金额”，V1 直接拒绝。
- 负数不自动取绝对值，也不自动把支出改成收入；负数输入必须回到确认页修正。
- 收入和支出的方向只由 `type` 表示，不把金额存成正负混合值。
- 支出和收入统计分别按 `type` 汇总，不通过金额正负猜测方向。

用户输入金额时，应按字符串解析到分，最多保留小数点后两位；超过两位要提示修改，不能静默四舍五入。数据库和后端计算使用整数，前端展示时才格式化为 `¥35.00` 等文字。前端显示支出或收入的颜色、符号不改变数据库中的正整数金额。

### 4.2 为什么不用浮点金额或负数金额

浮点数不适合作为财务数据的核心存储和计算形式，可能产生小数精度误差。负数同时表达方向和数值也会让分类、统计、编辑和新手理解变复杂。V1 已有明确的 `type`，因此“正整数分 + 独立收支类型”是最简单且一致的组合。

## 5. 收入和支出

`type` 是固定枚举，只有两个值：

| 内部值 | 用户显示 | 说明 |
| --- | --- | --- |
| `expense` | 支出 | 金额从用户可支配资金中支出。 |
| `income` | 收入 | 金额进入用户可支配资金。 |

V1 不加入 `refund`、`transfer`、`adjustment` 等类型。退款、账户间转账和复杂冲销如果未来确有需要，应先由主 Agent 重新定义产品和数据语义，再进行迁移；不能把它们临时塞进收入或支出。

## 6. 分类设计

### 6.1 A/B 方案比较

方案 A 是直接把“餐饮”“买菜/食品”等中文名称存进 `category`。它对新手直观、初期读取简单，但分类名称一旦改成“食品杂货”、改字或需要多语言，历史记录会被迫批量改名，名称也容易出现空格、大小写或同义词不一致。

方案 B 是在 `category` 中保存稳定内部 code，再把 code 映射为当前中文名称。它多了一层固定映射，但可以在不改历史账目 code 的情况下调整展示名称，也便于前端、后端和测试使用同一组值。

**V1 推荐方案 B。** `category` 字段仍然只有一个，字段名不改成多个版本；字段值使用下表的稳定 code。中文名称属于展示标签，不作为数据库主值。

### 6.2 V1 分类 code 与中文名称

| `type` | `category` code | 当前中文名称 |
| --- | --- | --- |
| `expense` | `dining` | 餐饮 |
| `expense` | `groceries_food` | 买菜/食品 |
| `expense` | `daily_necessities` | 日用品 |
| `expense` | `transportation` | 交通 |
| `expense` | `vehicle_fuel` | 车辆/加油 |
| `expense` | `housing` | 居住 |
| `expense` | `communication` | 通讯 |
| `expense` | `entertainment` | 娱乐 |
| `expense` | `children` | 孩子 |
| `expense` | `medical` | 医疗 |
| `expense` | `other_expense` | 其他支出 |
| `income` | `salary` | 工资 |
| `income` | `other_income` | 其他收入 |

规则和确认页面可以使用中文名称帮助新手选择，但保存前必须转换为唯一对应的 code。`expense` 只能使用支出分类，`income` 只能使用收入分类；这项匹配由后端/API 校验，避免收入账目保存为“餐饮”。V1 不允许用户自定义分类，不在本表之外临时增加 code。

### 6.3 分类名称调整边界

如果只是展示名称调整，例如把“通讯”改成“通信”，只需更新 code 到中文标签的映射，不修改历史 `category` 值。如果未来需要把一个分类拆成两个或把多个分类合并，不能只改文案掩盖语义变化；应由主 Agent 决定迁移规则并重新检查统计口径。

## 7. 日期和时间

### 7.1 `transaction_date`

`transaction_date` 是这笔消费或收入发生的最终账务日期，不是记录写入日期。它使用 SQLite `TEXT` 保存 `YYYY-MM-DD`，例如 `2026-08-29`，不保存时分秒和时区。

Data Agent 不负责把“昨天午饭”解析成日期。Classification 或后端解析流程先根据本机日期得到最终日期，确认页面允许用户修改，数据层只接收已经确认的有效日期。

V1 的最终日期边界：

- 未写日期或写“今天”时，默认当前本机日期。
- “昨天”和 `PROJECT.md` 规定的“前天”在解析阶段转换为本机日期减 1 天或减 2 天。
- `8月20日`、`8月20号` 按当前年份解释；明确年份的日期按用户给出的年份解释。
- 必须是真实日历日期；未来日期不允许保存，应提示用户修改。
- 数据库中不保存“今天”“昨天”等自然语言词，也不保存 `2026年8月20日` 这样的展示输入。

### 7.2 `created_at`、`updated_at`、`deleted_at`

- `created_at`：第一次点击保存并成功写入该行的时间。编辑、删除、恢复都不能改变它。
- `updated_at`：该行最近一次发生有效变更的时间。新增时先与 `created_at` 相同；编辑字段、软删除和恢复都更新它。
- `deleted_at`：软删除发生的时间；有效记录为 `NULL`。恢复时重新设为 `NULL`，同时更新 `updated_at`。

三个时间戳建议统一保存为带 `Z` 的 UTC ISO 8601 `TEXT`，例如 `2026-08-29T08:30:00Z`。用户界面如果需要显示时间，应按本机时区格式化，但不能用时间戳替代 `transaction_date`。

`transaction_date` 用于今天、本月统计；`created_at` 或 `updated_at` 只用于记录顺序、审计和编辑状态。不能用“创建时间在今天”推断“账务日期是今天”。

## 8. 备注和原始输入

### 8.1 `note`

`note` 是唯一的自由文字备注字段，可为空。保存规则如下：

- 前端和后端都应去除首尾空白；去除后为空则保存 `NULL`。
- 最长 200 个字符；超过长度时提示用户修改，不静默截断。
- 备注可以来自解析结果，也可以由用户在确认页或编辑页改写、清空。
- 没有备注时，列表可以显示空值状态，但数据库不写入伪造的“无备注”。
- 用户输入按普通文本保存和展示，不作为 HTML 或模板执行。

### 8.2 `original_text`

主 Agent 在数据模型验收检查点正式决定：V1 增加 `original_text` 字段，保存用户最初输入的一句话。

接受原因：

- Smart Ledger 的核心入口就是“一句话智能记账”，原始输入是解释识别结果的重要依据。
- 用户后续修改分类、备注或日期后，仍然可以追溯当时为什么得到这个识别建议。
- 后续优化规则时，可以用历史原句检查哪些表达没有覆盖。
- 未来若增加 AI 辅助分类，原始文本可以作为用户本机已有数据继续利用。
- 该字段只是一个文本字段，不引入商户、来源、导入、OCR、账号或云端能力。

保存规则：

- `original_text` 保存用户提交并用于生成确认页的原句。
- 如果用户在确认前返回并改写原句，最终保存的是改写后的那一句。
- 保存原始字符串本身，不去除首尾空白，不合并内部空白，不重写标点。
- 校验时可以用去除首尾空白后的副本判断是否有有效内容；如果全是空白，不能保存为正式账目。
- 最长 500 个字符；超过长度时提示用户缩短，不静默截断。
- 账目保存后，普通编辑只修改金额、类型、分类、备注和账务日期，不修改 `original_text`。
- `original_text` 不作为账单列表核心列展示；详情页或调试信息可以展示“原始输入”。
- 用户输入按普通文本保存和展示，不作为 HTML 或模板执行。

`original_text` 和 `note` 的区别：`original_text` 是用户最初说的完整句子，例如“昨天晚上买菜花了35块”；`note` 是确认后的备注，例如“买菜”。用户改备注不会改变原始输入。

## 9. 编辑规则

用户可以编辑 `amount_cents` 对应的金额、`type`、`category`、`note` 和 `transaction_date`。编辑是更新原行，不新建新行：

1. `id` 保持不变。
2. `created_at` 保持不变。
3. `original_text` 保持最初保存时的原句，不随普通编辑变化。
4. 被修改的业务字段保存成功后，`updated_at` 更新为新的 UTC 时间。
5. `deleted_at` 为 `NULL` 的记录才允许普通编辑；已删除记录先恢复或由撤销流程处理。
6. 编辑后的字段立即成为列表和首页统计的唯一依据；旧值不另存为第二笔账。
7. 如果编辑改变了 `type` 或 `category`，后端重新做收支与分类匹配校验。
8. 如果编辑改变了日期，首页统计按新日期计算；不依据 `created_at` 补回旧月份。

## 10. 删除、撤销和真正清理

### 10.1 两种方案比较

直接永久删除的优点是表里没有隐藏行、查询略简单；缺点是误删后必须把完整快照交给前端或临时缓存，再重新插入，应用重启、请求丢失或恢复失败时容易无法撤销，且可能丢失原来的 `id` 和时间信息。

软删除只需在同一行写入 `deleted_at`，撤销时把它恢复为 `NULL`，能够保留原账的 `id`、`created_at` 和所有业务字段，也不需要回收站表。它多了一个所有查询都必须过滤的规则，但对 V1 的“删除后立即撤销”要求更可靠。

**V1 推荐软删除。** 这不是回收站功能，也不新增第二张表：删除动作在 `transactions` 中设置 `deleted_at`，用户界面立即隐藏该账并提供撤销入口。

### 10.2 V1 行为边界

- 列表、首页统计、最近账单和重复提醒只处理 `deleted_at IS NULL` 的有效账目。
- 删除前必须二次确认；删除成功后提供当前页面的撤销入口。
- 撤销把同一行的 `deleted_at` 设回 `NULL`，保留 `id` 和 `created_at`，并更新 `updated_at`。
- V1 不做回收站页面、批量删除、跨设备恢复或自动永久清理。
- 软删除记录仍属于完整 SQLite 数据库的一部分，因此数据库备份会保留它们；这有利于文件级恢复，也意味着“从页面删除”不等于“从备份彻底擦除”。
- 真正物理清理需要另一个明确的维护/保留策略、备份提示和主 Agent 批准；当前不提供清理接口，不让普通删除承担不可恢复清理的含义。

## 11. 重复记账

现实中可能连续发生完全相同的消费，例如两次同价乘车或两次购买同价商品。因此数据库不得建立以下唯一约束，也不得因它们相同而拒绝写入：

`transaction_date + amount_cents + type + category + note`

V1 的重复提醒放在业务/API 层：在新账保存前，后端可以把当前待保存字段与最近一笔有效保存账的上述五个字段比较；完全相同时返回“可能重复”的提醒，由前端要求用户确认。该提醒不改变数据库约束，用户明确选择继续后仍可保存。已软删除的记录不参与普通重复提醒。

V1 采用“最近一笔相同账提醒”这一简单边界，不扫描所有历史账，也不自动合并、覆盖或删除重复记录。是否将编辑冲突也提示，可由 Backend/UX 在不改变数据库允许重复的前提下决定；不能把提醒做成强制唯一。

## 12. 首页统计口径

数据模型足以计算首页的三个指标，因为金额是整数分、方向是独立 `type`、日期是可比较的本地日期。

统计只使用已保存且未删除的记录：

- **今天支出**：`deleted_at IS NULL`、`type = 'expense'` 且 `transaction_date` 等于当前本机日期的 `amount_cents` 合计。
- **本月支出**：`deleted_at IS NULL`、`type = 'expense'` 且 `transaction_date` 位于当前本机月份的 `amount_cents` 合计。
- **本月收入**：`deleted_at IS NULL`、`type = 'income'` 且 `transaction_date` 位于当前本机月份的 `amount_cents` 合计。

统计口径补充：

- 待确认草稿没有数据库记录，不计入统计。
- 金额合计始终使用整数分，展示时再格式化为人民币金额。
- 编辑、软删除或恢复后，统计应依据当前行的最新状态重新计算。
- 没有数据时合计为 `0` 分，用户界面显示为 `¥0.00`。
- 不计算余额、不把收入减支出、不做分类占比或复杂报表。
- `created_at`、`updated_at` 不参与账务日期范围判断。

账单列表可使用 `transaction_date` 从新到旧排序；同一天内用 `updated_at` 从新到旧，再用 `id` 作为相同时间的稳定兜底。新建时 `updated_at = created_at`。这样新增和刚编辑保存的记录都有确定顺序，但不会改变统计口径。

## 13. SQLite V1 最小结构

### 13.1 是否需要第二张表

不需要。V1 是本地单用户、固定分类、无用户自定义分类、无外部来源、无账户和无同步的应用。一张 `transactions` 表已经能支持：

- 单笔新增、查看、编辑、软删除和撤销；
- 今天支出、本月支出、本月收入；
- 固定分类的保存和校验；
- 文件级 SQLite 备份。

现在增加 `categories` 表没有实际收益：它会增加 join、初始化数据、分类版本和迁移问题，而 V1 没有分类 CRUD 或分类元数据需求。未来分类可配置、分类多语言或分类层级真正出现时，再由主 Agent 决定是否迁移出独立表。

### 13.2 伪 SQL 结构说明

以下仅是给 Backend、Test 和 Review Agent 读取的结构说明，不执行、不创建真实数据库：

```sql
CREATE TABLE transactions (
    id INTEGER PRIMARY KEY,
    amount_cents INTEGER NOT NULL CHECK (amount_cents > 0),
    type TEXT NOT NULL CHECK (type IN ('expense', 'income')),
    category TEXT NOT NULL,
    note TEXT CHECK (note IS NULL OR length(note) <= 200),
    original_text TEXT NOT NULL CHECK (length(trim(original_text)) >= 1 AND length(original_text) <= 500),
    transaction_date TEXT NOT NULL,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    deleted_at TEXT
);

CREATE INDEX idx_transactions_date_status
    ON transactions (transaction_date, deleted_at);
```

说明：

- `type`、金额正数、备注长度和原始输入长度是数据库可以直接表达的简单约束。
- `category` 的 code 白名单以及 `category` 与 `type` 的匹配由后端/API 使用固定分类目录校验；不把一长串易变分类名称堆进复杂 SQL `CHECK`。
- `transaction_date` 的真实日历有效性和“不允许未来日期”由后端按本机日期校验；SQLite 的 `TEXT` 声明本身不等于日期校验。
- `created_at`、`updated_at` 由后端生成，不能信任前端传入任意时间；`deleted_at` 只由删除/恢复动作写入。
- 不设置任何业务唯一约束，不建立外键，不建立触发器，不建立第二张核心表。

## 14. 未来扩展边界

这些内容只做扩展分析，本轮不实现，也不提前增加空字段。

| 未来方向 | 当前是否预留字段 | 未来可能的迁移方向 |
| --- | --- | --- |
| V2 微信/支付宝账单文件导入 | 否 | 增加输入来源与导入流程设计；若来源提供稳定外部编号，再评估 `source` 和 `external_transaction_id`，并制定幂等/重复规则。导入结果仍先成为待确认草稿。 |
| V3 支付截图 OCR | 否 | OCR 只生成金额、日期、分类、备注和原始输入建议；原图、OCR 置信度和识别批次应另行设计，不能直接塞入 V1 `transactions`。 |
| V4 通知、短信或其他合法来源 | 否 | 先确认平台权限、用户授权和来源可靠性，再设计来源/外部标识/采集记录；不能把通知内容直接当已确认账目。 |
| AI 辅助分类 | 否 | 可在确认前增加建议和置信度模型，但最终仍写入同一套 `type`、`category` 和其他正式字段；原句是否外发需要单独授权。 |
| 商户 | 否 | 若未来需要商户筛选、汇总或规范化，再决定新增 nullable `merchant` 或独立商户模型；当前只可作为 `note` 的文字内容。 |

未来所有输入来源都应先经过同一套“建议 -> 用户确认 -> 保存”的边界。`original_text` 可保存“形成这笔账的原始文本”，但不能替代未来导入来源、商户、外部编号、OCR 批次或 AI 置信度。未来字段加入时必须有 SQLite migration、旧备份兼容方案、API 版本说明和测试，不得由实现 Agent 顺手添加。

## 15. 备份边界

`smart-ledger.sqlite` 是 V1 的完整账目数据库，由后端放在稳定的应用数据目录中。V1 备份按 `PROJECT.md` 的决定使用 SQLite 安全备份机制生成，例如：

`smart-ledger-backup-YYYYMMDD-HHMMSS.sqlite`

一个备份文件应包含：

- `transactions` 表的全部已保存记录；
- 当前数据库 schema 和索引；
- 有效账目及其 `id`、金额分、类型、分类 code、备注、原始输入、账务日期、时间戳；
- 软删除记录及其 `deleted_at`，因为它们仍属于完整数据库状态。

一个备份文件不包含：

- 未确认的自然语言输入和临时识别草稿；已确认并保存为 `original_text` 的原句属于 `transactions` 表，会进入备份；
- 浏览器 `localStorage`、IndexedDB 或页面缓存；
- 云端副本、账号、导入任务、OCR 原图或运行日志。

备份动作应在数据库安全备份机制下完成，不能把“正在写入的 SQLite 文件直接复制”当作一致性保证。V1 做本地备份下载，不做云备份、云同步、定时备份、JSON/CSV 导出或复杂恢复中心。恢复入口和用户如何选取备份文件属于后续产品/Backend 决策，但备份文件本身应保持完整 SQLite 数据库边界。

## 16. 最终示例：用户看到什么，数据库保存什么

以下假设保存当天本机日期为 `2026-08-29`，因此“昨天”是 `2026-08-28`。时间戳只作示意。示例中的金额都以正整数分保存，绝不以负数表达支出。

| 用户输入 | 用户确认后看到的结果 | SQLite/API 内部结果示意 |
| --- | --- | --- |
| `35块买菜` | `¥35.00`，支出，买菜/食品，备注“买菜”，日期 `2026-08-29`，原始输入“35块买菜” | `id=1`，`amount_cents=3500`，`type="expense"`，`category="groceries_food"`，`note="买菜"`，`original_text="35块买菜"`，`transaction_date="2026-08-29"` |
| `昨天午饭18块` | `¥18.00`，支出，餐饮，备注“午饭”，日期 `2026-08-28`，原始输入“昨天午饭18块” | `id=2`，`amount_cents=1800`，`type="expense"`，`category="dining"`，`note="午饭"`，`original_text="昨天午饭18块"`，`transaction_date="2026-08-28"` |
| `300加油` | `¥300.00`，支出，车辆/加油，备注“加油”，日期 `2026-08-29`，原始输入“300加油” | `id=3`，`amount_cents=30000`，`type="expense"`，`category="vehicle_fuel"`，`note="加油"`，`original_text="300加油"`，`transaction_date="2026-08-29"` |
| `工资8000` | `¥8,000.00`，收入，工资，备注“工资”，日期 `2026-08-29`，原始输入“工资8000” | `id=4`，`amount_cents=800000`，`type="income"`，`category="salary"`，`note="工资"`，`original_text="工资8000"`，`transaction_date="2026-08-29"` |
| `20打车` | `¥20.00`，支出，交通，备注“打车”，日期 `2026-08-29`，原始输入“20打车” | `id=5`，`amount_cents=2000`，`type="expense"`，`category="transportation"`，`note="打车"`，`original_text="20打车"`，`transaction_date="2026-08-29"` |

每行还会由数据库/后端生成 `created_at`、`updated_at`，初始 `deleted_at = NULL`。例如第一行的内部完整形状可以写成：

```text
id: 1
amount_cents: 3500
type: expense
category: groceries_food
note: 买菜
original_text: 35块买菜
transaction_date: 2026-08-29
created_at: 2026-08-29T08:30:00Z
updated_at: 2026-08-29T08:30:00Z
deleted_at: NULL
```

这里“买菜/食品”和 `groceries_food` 是同一个分类概念的两种表现：前者给用户看，后者在数据中保存。`35` 元和 `3500` 分也是同一金额概念的两种表现。支出仍保存 `3500`，不是 `-3500`。`original_text` 保存用户最初输入的完整句子，`note` 保存用户确认后的备注。

## 17. 给后续 Agent 的读取建议

### 主 Agent

先确认本文件的最终决策：统一字段名、稳定 category code、正整数分、`YYYY-MM-DD`、`original_text` 追溯字段、`deleted_at` 软删除和允许重复账。后续 Agent 不得因为“未来可能有用”提前加入 `merchant`、`source`、外部编号或导入/OCR 字段。范围争议回到主 Agent，不由实现 Agent 自行扩大。

### Classification Agent

只负责把自然语言解析成待确认建议，最终输出应能填入 `amount_cents`、`type`、`category`、`note`、`original_text`、`transaction_date`。使用本文件的 category code 与中文映射；`original_text` 保留完整原句，`note` 是提取或用户确认后的备注，不创建新分类，不绕过确认直接保存。

### UX/UI Agent

使用中文标签展示金额、收入/支出、分类、备注和日期；让待确认建议与已保存账单有明确区别。`original_text` 可在详情页或确认页作为“原始输入”展示，但不要把它变成账单列表主列。设计编辑、删除二次确认、软删除后的撤销和可能重复提醒时，不让用户看到 code、`deleted_at` 或把负号当作收支语义。日期展示来自 `transaction_date`，不要用创建时间替代。

### Frontend Agent

按本文件字段名消费 API：金额用 `amount_cents` 做整数展示转换，收支用 `type`，分类用 `category` code 映射标签，空备注按 `null` 处理，原始输入使用 `original_text`。不要用 `amount` 浮点数作为主状态，不用 `localStorage` 或 IndexedDB 建立第二个账目主库，不另造 `raw_text`、`input_text` 等同义字段。

### Backend Agent

实现时以一张 `transactions` 表为边界，重复执行服务端校验：金额大于 0、最多两位小数转换、`type` 枚举、分类与收支匹配、备注长度、原始输入长度、有效日期和未来日期拒绝。新增、编辑、软删除、恢复都遵守时间戳规则；普通编辑不改 `original_text`；所有普通查询和统计过滤 `deleted_at IS NULL`；重复提醒不做数据库唯一约束。数据库操作使用参数绑定，备份使用 SQLite 安全备份机制。

### Test Agent

覆盖正整数分、0/负数拒绝、超过两位小数、全部 category code、收入/支出匹配、今天/昨天/历史日期/未来日期、备注为空和超长、`original_text` 必填和超长、编辑后 `id`、`created_at` 与 `original_text` 不变、`updated_at` 变化、删除撤销、重复账允许保存以及三个首页统计口径。还要验证关闭并重新打开后数据来自同一 SQLite 文件，备份包含完整表结构和记录。

### Review Agent

逐项审查实现是否只使用一套字段命名，是否遗漏 `original_text` 或把它混同为 `note`，是否误加 `merchant`、`source`、账户或同步字段，是否把金额存成浮点/负数，是否用永久删除破坏撤销，是否用唯一约束阻止真实重复账，以及统计是否错误包含待确认或软删除记录。

## 18. 后续仍需决定的事项

本文件已经确定 V1 数据概念和保存规则。后续 Agent 仍需决定的是实现和界面层细节，不应改变本模型：

1. Backend 的具体 API 路径、请求/响应封装和错误码。
2. Frontend/UX 的人民币展示格式、分类选择器样式、软删除撤销入口有效时长和重复提醒文案。
3. 备份按钮的具体页面位置，以及 V1 是否提供文件替换式恢复入口；当前只冻结“完整 SQLite 安全备份”，不冻结复杂恢复中心。
4. SQLite 文件的实际应用数据目录、默认端口和运行包装方式；这些不改变表结构。
5. 如果未来确实需要物理清理软删除记录、商户、来源、外部编号、OCR 原文或 AI 置信度，主 Agent 必须先确认产品范围、迁移方式、备份影响和测试，再进入下一版本设计。

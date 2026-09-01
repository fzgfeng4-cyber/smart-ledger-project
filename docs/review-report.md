# Smart Ledger V1 最终独立 Review 报告

- Review 日期：2026-08-30
- Review 范围：V1 产品、架构、数据模型、分类规则、API、Frontend、Backend、SQLite、安全、测试和文档一致性。
- 本轮读取：`PROJECT.md`、`docs/product-v1.md`、`docs/technical-research.md`、`docs/data-model.md`、`docs/classification-rules.md`、`docs/ui-plan.md`、`docs/api-contract.md`、`docs/integration-report.md`、`docs/test-report.md`、`skills/review.md`。
- 本轮只审查，不修改 `frontend/`、`backend/`、测试、API、数据模型、分类规则或 UI 方案；唯一正式写入文件为本报告。
- 验证方式：静态阅读、隔离 SQLite 运行验证、Backend 自动测试、Frontend TypeScript 检查，以及真实 Frontend 页面 DOM 验证。正式数据库只读检查，未清库、未删除、未导入。

## 1. Review 范围

已完整审查 `frontend/` 和 `backend/`，并逐项对照 V1 产品、技术、数据、分类、UI、API、联调和测试文档。

本轮独立验证结果包括：

- `backend/test_main.py`：`24 passed, 1 warning`。
- `frontend`：`npm run typecheck` 通过；既有 `docs/test-report.md` 记录 `npm run build` 和 18 项验收均通过。
- 临时 SQLite 空库：摘要、列表和真实 Frontend 首页运行态均验证通过。
- 正式 `backend/data/smart-ledger.sqlite`：只读 `PRAGMA integrity_check` 为 `ok`，当前总行数 11、有效行 9、软删除行 2，未改变现有数据。

## 2. 产品范围检查

结论：**已确认正常**。Frontend 和 Backend 只实现本地单用户、一句话规则记账闭环，没有发现 V1 明确禁止的功能入口或调用。

未发现以下超范围实现：微信/支付宝自动读取、淘宝或银行同步、通知采集、OCR、截图识别、CSV/Excel 导入、登录注册、多用户、云同步、大模型 AI、复杂图表/报表、预算、投资贷款、社交或支付来源管理。

`frontend/src/api.ts` 默认使用真实 Backend，只有显式设置 `VITE_USE_MOCK=true` 时才使用 `mock-api.ts`；正常运行不会误进 mock。mock 仅属于显式演示路径，不是正式数据源。

V1 必要闭环均有实现：一句话输入、规则解析、确认页、五个业务字段修改、保存、账单列表、账单编辑、软删除、10 秒撤销、今天支出、本月支出、本月收入和 SQLite 备份。识别结果不会在解析接口阶段写入数据库。

## 3. 架构检查

架构为 Vue 3 + TypeScript + Vite -> FastAPI -> SQLite，Frontend 通过统一 `frontend/src/api.ts` 调用 Backend，Backend 通过 `LedgerService` 处理校验、SQLite 操作、统计和备份，符合本地个人 V1 的简单边界。

Backend 只有一个核心 `transactions` 表，没有提前引入用户、账户、分类管理、审计或同步等企业级结构。同步 SQLite 连接和 `BEGIN IMMEDIATE` 对本机单用户 V1 足够；未发现需要因大型互联网系统标准而扩大范围的问题。

Backend 默认绑定方式由启动命令控制；既有联调和本轮临时运行均使用 `127.0.0.1`。CORS 只允许 `http://127.0.0.1:5173` 和 `http://localhost:5173`，没有通配来源。

## 4. 数据模型检查

结论：**已确认正常**。

SQLite `transactions` 表正好包含以下 10 个核心字段：

`id`、`amount_cents`、`type`、`category`、`note`、`original_text`、`transaction_date`、`created_at`、`updated_at`、`deleted_at`。

已核对 `backend/main.py:959-976` 的建表语句和正式数据库实际列结构：

- `amount_cents` 由 API 严格要求为正整数分；不接受浮点、0、负数或超出 SQLite 整数范围的值。
- `type` 仅允许 `expense` 和 `income`；金额方向不使用正负号表达。
- `category` 使用固定稳定 code，并由 Backend 校验与 `type` 匹配。
- `note` 可空，首尾空白归一为 `NULL`，最多 200 个字符。
- `original_text` 非空、最多 500 个字符；解析保留原始输入，普通编辑接口不允许覆盖它。
- `transaction_date` 使用有效的 `YYYY-MM-DD`，不能保存未来日期。
- `created_at`、`updated_at`、`deleted_at` 的读写边界符合文档；删除和恢复会更新 `updated_at`，不会改写 `created_at`。

未发现 `amount`、`money`、`amountCents`、`transactionDate` 等第二套 API 或数据库主字段。

## 5. Classification 检查

结论：核心规则大体符合 V1，指定主要案例通过；发现 1 个一般问题和 1 个文档口径建议。

已独立验证或由自动测试覆盖的关键结果：

| 输入 | 结果 |
|---|---|
| `5块买菜` | `500` 分、`expense`、`groceries_food`，可进入确认保存 |
| `8000工资` | `800000` 分、`income`、`salary`；因裸数字产生确认提示 |
| `带孩子吃饭86` | `8600` 分、`expense`、默认 `dining`，同时提示 `CATEGORY_CONFLICT`，没有静默吞掉孩子场景 |
| `35` | 金额候选保留，方向和分类为空，`needs_input`，不能直接保存 |
| `买菜` | 缺金额，`needs_input`，不能直接保存 |
| `买菜35又打车20` | `MULTIPLE_AMOUNTS`，不自动拆账，不自动选第一笔或最后一笔 |

规则使用正则、关键词和固定优先级，不依赖云端大模型。金额、日期会先从解析副本中识别，`original_text` 不会被清理文本覆盖。

**一般问题 G-3：`工资到账8000` 的分类优先级与规则文档不一致。** `backend/main.py:513-530` 同时命中 salary 和 generic `到账`，`_choose_category` 在多个收入分类时默认 `other_income` 并给出歧义提示；而 `docs/classification-rules.md:128,166` 明确把“工资到账”归入 `salary`，并规定工资优先。用户仍可在确认页改为工资，未造成静默错误保存，但默认建议不符合冻结规则。

`8000工资` 额外出现 `BARE_AMOUNT` 确认提示。该实现符合产品规则中“无单位数字必须核对”的原则，但 `docs/classification-rules.md:339` 的案例表写成“无额外补充”，存在文档口径不一致，列入建议优化而非功能阻塞。

## 6. API 检查

结论：**已确认正常**。逐项核对 `docs/api-contract.md` 与 `backend/main.py`、`frontend/src/api.ts`：

| 方法 | 路径 | 检查结论 |
|---|---|---|
| POST | `/api/parse` | 只解析，不保存；返回草稿、状态、缺失字段和 warnings |
| GET | `/api/categories` | 返回固定 13 个分类 code、中文名和 type |
| POST | `/api/transactions` | 严格校验后保存；成功 `201`，重复提醒 `200` |
| GET | `/api/transactions` | 只返回未软删除记录，支持 `page/page_size/total/has_next` |
| GET | `/api/transactions/{id}` | 返回有效账目；不存在或已删除为 `404` |
| PUT | `/api/transactions/{id}` | 只允许五个可编辑业务字段，返回更新后的完整 Transaction |
| DELETE | `/api/transactions/{id}` | 写入 `deleted_at`，返回撤销窗口信息 |
| POST | `/api/transactions/{id}/restore` | 10 秒内恢复；过期或状态不符为 `409` |
| GET | `/api/summary` | 返回三个整数分统计字段 |
| GET | `/api/backup` | 返回完整 SQLite 文件下载 |

Backend 对未知字段、缺失字段、类型、金额、分类、日期、备注、原始输入和重复确认标志均有校验。错误统一为 `{error:{code,message,details?}}`，Frontend 展示普通中文，不展示 traceback、SQLite exception 或 SQL。

## 7. Frontend 检查

结论：核心确认和编辑流程符合 UI 方案；发现 2 个一般问题。

已确认正常：

- 默认真实调用 Backend；mock 需要显式环境变量。
- 确认页展示原始输入、金额、收入/支出、分类、备注和日期；金额、方向、分类、备注、日期均可修改，`original_text` 在编辑状态只读。
- 缺关键字段、未来日期、多金额和未处理分类提示时保存按钮不可用。
- 保存、编辑、删除、撤销、重复提醒和错误状态都有中文反馈。
- `v-for` 普通插值渲染用户输入，没有 `v-html`、`innerHTML` 或模板执行路径。
- `docs/test-report.md` 已记录 375px 手机窄屏检查通过；CSS 对列表行、工作页操作区和日期输入做了响应式处理，未见明显结构重叠。

**一般问题 G-1：账单列表实际只显示第一页 50 条。** `frontend/src/pages/TransactionsPage.vue:18` 固定请求 `page=1,page_size=50`，只保存 `.items`，没有使用 `total` 或 `has_next`，模板 `:55-56` 还将当前数组长度标为“全部账目”。Backend 已提供分页能力，但当有效账目超过 50 条时，用户无法通过页面查看全部账目，且总数会误报。该问题不影响少量个人账目和核心保存流程，但与“查看全部有效账目”及长期自用目标不一致。

**一般问题 G-2：列表页和顶部“记一笔”入口在无待确认草稿时不会进入记账工作页。** `AppHeader.vue:32-34` 和 `TransactionsPage.vue:40-42` 直接导航到 `/transactions/new`；`WorkPage.vue:56-60` 在没有 `pendingDraft` 时立即返回首页。因此从账单页点击该按钮的实际结果是回到首页，而不是进入文档约定的账目工作页或可直接输入状态。首页快速输入仍可用，存在绕行路径，所以不属于交付阻塞，但入口行为与 UI 方案不一致。

## 8. Backend 检查

结论：**已确认正常**，未发现严重安全或数据正确性问题。

- FastAPI 路由和 `LedgerService` 边界清楚，单文件规模对 V1 尚可，不需要为此引入新框架或复杂分层。
- 请求体和查询参数均经过明确校验；金额使用整数分；日期使用真实日历校验；未来日期被拒绝。
- SQL 使用参数绑定，没有危险 SQL 拼接；写入有事务和回滚；连接在 `finally` 中关闭，并设置了 SQLite `busy_timeout`。
- 异常处理覆盖业务错误、请求校验、HTTP、SQLite 和未预期异常，返回普通中文 500，不泄露 traceback。
- 备份使用 SQLite `Connection.backup()` 写入临时 `.sqlite`，响应完成后删除临时文件，没有把用户路径直接交给下载接口。
- CORS 是本地明确来源列表，未过度开放；`allow_credentials=False`。
- 分类解析规则主体集中在 Backend 常量和函数中，没有散落为多套生产规则。

## 9. SQLite 检查

结论：核心结构和行为**已确认正常**。

- 正式数据库只有 `transactions` 一张核心表和 `idx_transactions_date_status` 一个必要索引，没有不必要的 categories、users、accounts、audit 或同步表。
- 列表、详情、统计和重复提醒均以 `deleted_at IS NULL` 为有效账目边界。
- DELETE 是软删除；restore 恢复同一行并保留 `id`、`created_at`；恢复后重新计入列表和统计；没有垃圾桶或物理清理接口。
- 重复提醒没有唯一约束，只比较最近约 10 分钟内最后一笔有效账；用户确认后仍可保存真实重复账。
- `today_expense`、`month_expense`、`month_income` 均按 `amount_cents` 和 `transaction_date` 聚合，排除软删除行。
- 备份文件为可读取的完整 SQLite 文件，并保留软删除行，符合文件级恢复边界。

**一般问题 G-4：默认 SQLite 放在 Git 工作区且当前没有根目录或 Backend 的 `.gitignore`。** `backend/main.py:22` 将路径固定为 `backend/data/smart-ledger.sqlite`；当前 `git status --short --untracked-files=all` 明确显示该数据库为未跟踪文件。`docs/technical-research.md:138,209` 要求数据库位于稳定应用数据目录且不提交 Git。当前不会通过 API 远程暴露，但存在误提交、误分享个人财务数据和把运行数据混入代码交付物的真实风险。正式交付前不应把该文件随源码公开；路径和忽略策略建议纳入当前维护小版本处理。

## 10. 安全检查

结论：**已确认正常，无严重安全问题**。

- 未发现 API 可控的文件路径、路径遍历、任意文件覆盖或任意文件下载；备份路径由服务端临时生成。
- 未发现危险 SQL 拼接；用户字段均通过参数绑定写入或查询。
- Vue 用户输入使用普通插值，`original_text` 和 `note` 没有 HTML 执行路径，XSS 风险控制符合本地 V1 标准。
- 400/404/409/500 响应不包含 Python traceback、SQLite 错误或内部 SQL。
- 后端 CORS 没有使用 `*`，只允许两个本地开发来源。
- 无登录、账号、应用级加密属于已确认的 V1 不做项，不因缺失把它们判为问题。
- G-4 是工作区数据保护和交付卫生问题，当前未达到必须阻断本地 V1 使用的严重等级。

## 11. 测试证据检查

结论：现有证据足以支持本地个人 V1 交付，但仍有边界覆盖可加强。

`backend/test_main.py` 的 24 个测试覆盖了 14 个正常解析样例、空输入、无金额、只有金额、多金额、分类冲突、负数、未来日期、原文保留且解析不落库、13 个分类、CRUD、编辑、软删除、恢复、统计、非法值、重复提醒、备份、非法 JSON、错误类型和撤销过期。

本轮用隔离可写临时目录重跑得到：

```text
24 passed, 1 warning in 1.66s
```

`frontend` 的 `npm run typecheck` 通过；`docs/test-report.md` 记录了 Frontend build、真实 Backend/SQLite 联调、18 项验收、桌面和 375px 浏览器检查通过。测试报告此前没有清空正式数据库运行空库页面，本轮已使用独立数据库补做，见第 13 节。

剩余测试建议包括：无效日历日期、暂不支持的日期、多个日期、`工资到账8000` 优先级、备注空白归一、原文长度上限、未知字段、分页参数、CORS、时间戳不变量和异常处理路径。它们不会推翻当前 24 个测试和 18 项验收对 V1 主闭环的支持，列为建议优化 S-2。

## 12. Warning 分析

当前唯一测试 Warning 为 `StarletteDeprecationWarning`，实际运行版本为：FastAPI `0.141.1`、Starlette `1.6.0`、httpx `0.28.1`。

具体来源是依赖环境中的 `starlette/testclient.py:33-50`：Starlette TestClient 先尝试导入 `httpx2`，未安装时回退到 `httpx` 并发出“使用 `httpx` 与 `starlette.testclient` 已弃用，请安装 `httpx2`”的警告；`fastapi/testclient.py:1` 只是重新导出 Starlette 的 TestClient。它发生在测试客户端兼容层，不发生在生产 FastAPI 请求处理路径。

判断：

- 当前 V1 不受影响；24 个测试全部通过，生产服务启动和 API 请求不依赖 TestClient。
- 不会很快导致当前功能失效，因此不能按严重问题处理。
- `backend/requirements.txt` 使用宽范围 `fastapi>=0.115,<1`、`httpx>=0.27,<1`，未来依赖解析漂移后可能把告警升级为兼容性失败。
- 建议在当前维护小版本或 CI 维护中锁定经验证的 FastAPI/Starlette/httpx 组合，或按当前 Starlette 建议评估 `httpx2` 测试依赖；这是测试依赖小改动，不需要改业务代码。
- 在尚未处理前应保留告警记录，依赖升级必须重跑完整测试，不应简单屏蔽 Warning。

此项列为建议优化 S-3，不阻塞 V1 交付。

## 13. 空数据库验证结果

结论：**通过**，且没有触碰正式测试数据。

验证使用隔离临时 SQLite 文件启动 Backend，并用 `VITE_API_BASE_URL=http://127.0.0.1:18000` 启动 Frontend 于允许的 `http://127.0.0.1:5173` 来源。检查结果：

- `GET /api/summary` 返回 `today_expense_cents=0`、`month_expense_cents=0`、`month_income_cents=0`。
- `GET /api/transactions?page=1&page_size=50` 返回 `items=[]`、`total=0`、`has_next=false`。
- 使用隔离 Chrome 访问真实 Vite 页面并导出运行态 DOM，确认出现三个 `¥0.00`、`还没有账目`、`快速记账` 和输入入口。
- DOM 中没有出现“统计暂不可用”或账单加载失败状态。
- 验证结束后停止临时服务并清理临时数据库、临时浏览器配置和临时测试目录。

正式 `backend/data/smart-ledger.sqlite` 仍保持只读核对结果：完整性 `ok`，总行数 11，有效 9，软删除 2。

## 14. 文档一致性

总体结论：产品、技术路线、数据模型、分类、UI、API、联调和测试文档与代码主体一致；发现以下文档维护项：

- `PROJECT.md:261,278-293` 仍写成“当前第 8 步”“Test Agent 未开始”“Review Agent 未开始”，与已经存在的 `docs/test-report.md` 以及本次最终 Review 状态滞后。列为建议优化 S-4。
- `docs/classification-rules.md:339` 将 `8000工资` 写成没有额外确认，但 `docs/product-v1.md:56` 和当前实现要求裸数字核对。建议统一文档和测试口径，关联 G-3/S-1。
- `docs/technical-research.md:138,209` 要求应用数据目录和不提交 Git，而当前 Backend 默认路径仍在工作区，已列为 G-4。
- `docs/integration-report.md` 记录的是第 8 步当时的浏览器自动化限制，`docs/test-report.md` 是后续第 9 步测试结果；两者属于阶段时间差，不构成互相否定，但后续可在 PROJECT 状态更新时补充阶段关系。

## 15. 严重问题

**数量：0。**

没有发现必须修复后才能交付的产品、数据、API、SQL、安全、删除恢复、统计或空库问题。没有 traceback 泄露、危险 SQL、任意文件下载、XSS 执行路径、物理删除误用或 AI/云同步越界实现。

## 16. 一般问题

**数量：4。**

1. **G-1：账单列表只加载首 50 条，忽略 Backend 分页结果。** 账目超过 50 条时无法查看全部，且“全部账目”计数不准确。见 `frontend/src/pages/TransactionsPage.vue:18,53-56`。
2. **G-2：列表页和顶部“记一笔”在无待确认草稿时回首页。** 入口存在但行为不符合列表进入工作页的 UI 方案。见 `frontend/src/components/AppHeader.vue:32-34`、`frontend/src/pages/TransactionsPage.vue:40-42`、`frontend/src/pages/WorkPage.vue:56-60`。
3. **G-3：`工资到账8000` 默认落到 `other_income` 并提示歧义，没有执行文档规定的工资优先。** 用户可以修正，未静默保存错误分类。见 `backend/main.py:507-563`、`docs/classification-rules.md:128,166`。
4. **G-4：正式 SQLite 位于 Git 工作区且未被根目录/Backend `.gitignore` 忽略。** 存在误提交和误分享个人账单数据的风险。见 `backend/main.py:22`、`docs/technical-research.md:138,209`。

这些问题均有明确绕行或不影响少量本地账目的核心闭环，但建议在当前 V1 维护批次处理，G-4 在任何源码公开或提交前优先处理。

## 17. 建议优化

**数量：4。**

1. **S-1：统一 `8000工资` 的规则文档和运行口径。** 保留“裸数字需核对”的产品原则，并在分类回归测试中加入 `工资到账8000`，防止工资优先级回退。
2. **S-2：补充边界测试。** 增加日期非法/不支持/多日期、备注和原文长度、未知字段、分页参数、CORS、时间戳不变量和统一异常响应测试。
3. **S-3：处理 Starlette 测试依赖告警。** 评估 `httpx2` 或锁定兼容依赖组合；不修改业务代码，不简单屏蔽 Warning。
4. **S-4：更新项目进度文档。** 将 `PROJECT.md` 的当前阶段、Test Agent、Review Agent 和下一步更新为最终 Review 状态，并保留本报告作为交付证据。

## 18. 已确认正常

- V1 范围保持为本地单用户一句话智能记账，没有超范围功能。
- Frontend 正式运行默认调用真实 Backend，mock 仅显式启用。
- 一句话解析不会自动保存；用户确认前不能产生正式账目。
- 指定的 `5块买菜`、`8000工资`、`带孩子吃饭86`、`35`、`买菜` 和多金额案例行为符合核心安全边界。
- 五个用户可编辑业务字段和 `original_text` 只读追溯字段边界正确。
- Transaction 十字段、整数分、固定 type/category code、原文保留和日期校验正确。
- API 路径、method、snake_case 字段、状态码和错误结构与契约一致。
- SQLite 只有必要核心表；软删除、统计排除、恢复和备份行为正确。
- 重复账只 warning，不建立唯一约束，不阻止用户保存真实重复交易。
- SQL 参数绑定、异常隐藏、普通中文错误提示、Vue 文本转义和本地 CORS 均符合 V1 标准。
- Backend 24 个自动测试通过，Frontend typecheck 通过，既有 18 项验收和移动端证据支持核心交付。
- 独立临时空库运行态通过：三个统计为 `¥0.00`，列表为空，显示“还没有账目”和快速记账入口。

## 19. 是否建议 V1 交付

**建议正式交付 Smart Ledger V1（本地个人使用），无交付阻塞。**

交付判断基于：严重问题为 0，核心闭环、数据完整性、API、软删除恢复、统计、备份、错误处理和空数据库状态均已验证。4 个一般问题应进入当前 V1 维护清单；特别是 G-4 在源码提交、压缩分享或公开仓库前必须先处理数据文件路径和忽略边界。Starlette Warning 不影响本地 V1 功能，但应保留记录并在依赖维护时处理。

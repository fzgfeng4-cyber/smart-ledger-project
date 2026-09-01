# Smart Ledger V1 Review 问题修复报告

- 修复日期：2026-08-30
- 执行角色：主 Agent
- 修复范围：仅处理 `docs/review-report.md` 中 4 个“一般问题”。
- 明确未处理：Review 报告中的 4 个“建议优化”不在本轮范围内。
- 验证数据库：使用临时 SQLite `tmp-review-fix/smart-ledger-review.sqlite` 回归验证，未修改正式 `backend/data/smart-ledger.sqlite` 中的真实账目数据。

## 1. 问题处理结果

| Review 问题 | 处理结果 | 修改文件 |
| --- | --- | --- |
| G-1：账单列表只加载首 50 条 | 已修复。列表页使用 API 契约已有的 `page/page_size/total/has_next`，新增“加载更多”，用户可继续查看 50 条之后的账目。 | `frontend/src/pages/TransactionsPage.vue` |
| G-2：“记一笔”入口行为不一致 | 已修复。无待确认草稿时，账目工作页显示“一句话记账”输入状态，不再空跳回首页或列表；顶部入口在工作页内不会切走当前未保存内容。 | `frontend/src/pages/WorkPage.vue`、`frontend/src/App.vue`、`frontend/src/components/AppHeader.vue` |
| G-3：`工资到账8000` 分类不一致 | 已修复。收入分类选择中 `salary` 优先；`工资到账8000` 解析为 `category = salary`，并补充后端回归测试。 | `backend/main.py`、`backend/test_main.py` |
| G-4：真实 SQLite 数据库没有被 Git 忽略 | 已修复。新增根目录 `.gitignore`，忽略 `backend/data/`、`*.sqlite`、SQLite wal/shm、Python cache、前端构建产物、依赖目录、本地环境文件和本轮临时验证目录。 | `.gitignore` |

## 2. 为什么这样修

### 2.1 账单列表

后端 API 已经支持简单分页，因此不需要改 API 契约，也不需要增加筛选、搜索或复杂无限滚动。前端只增加“加载更多”按钮，并显示“已显示 X / 共 Y 笔”，保持 V1 简单稳定。

### 2.2 记一笔入口

V1 的核心流程仍然是“一句话输入 -> 解析 -> 确认 -> 保存”。本轮没有增加复杂草稿管理系统。修复后的行为是：

- 从首页或账单页点击“记一笔”：进入账目工作页的输入状态。
- 输入后解析：同页进入确认状态。
- 已在账目工作页时点击顶部“记一笔”：不切走当前页面，提示“请先保存或返回，避免丢失当前内容。”

这样不会悄悄丢失用户当前未保存内容，也不会创建新的页面或功能。

### 2.3 工资分类

`工资到账8000` 同时命中“工资”和“到账”。冻结规则要求工资类进入 `salary`，所以后端在收入分类候选里优先选择 `salary`。`GET /api/categories` 仍然返回原有固定 code，前端显示仍来自该正式分类目录，没有引入第二套分类。

### 2.4 Git 忽略

SQLite 文件是个人账目数据，不应随源码提交或分享。本轮只增加忽略规则，不删除、不移动、不清空现有数据库。当前 `backend/data/smart-ledger.sqlite` 尚未被 Git 跟踪；如果未来已经跟踪，需要使用 Git 从索引移除但保留本地文件，不能删除真实数据库。

## 3. 回归测试结果

| 验证项 | 结果 | 证据 |
| --- | --- | --- |
| 超过 50 条账目后继续查看 | 通过 | 临时 SQLite 写入 61 条有效记录；`GET /api/transactions?page=1&page_size=50` 返回 50 条且 `has_next=true`；第二页返回 11 条。Chrome headless + CDP 显示“已显示 50 / 共 61 笔”和“加载更多”，点击后页面显示第二页数据并变为“已显示 61 / 共 61 笔”。 |
| “记一笔”入口行为统一 | 通过 | Chrome headless + CDP 打开 `/transactions/new?source=transactions`，页面显示“记一笔”“一句话记账”“等待输入”“返回账单”，未跳回首页或列表。 |
| 草稿不会意外丢失 | 通过 | Chrome headless + CDP 在新增工作页输入并解析 `35块买菜`，形成确认草稿后点击顶部“记一笔”，页面仍停留在确认账目状态并显示“请先保存或返回，避免丢失当前内容。” |
| `工资到账8000` 分类一致 | 通过 | `POST /api/parse` 返回 `type=income`、`category=salary`、`note=工资`、`original_text=工资到账8000`。 |
| `GET /api/categories` 分类目录 | 通过 | 返回 13 个固定分类，`salary` 显示为“工资”，`other_income` 显示为“其他收入”。 |
| 真实 SQLite 文件不会被 Git 误提交 | 通过 | `git check-ignore -v backend/data/smart-ledger.sqlite` 命中 `.gitignore:1:backend/data/`；`git status` 不再显示该数据库文件。 |
| 原有一句话记账 | 通过 | `35块买菜` 解析为 `groceries_food`，确认后通过真实 API 写入临时 SQLite。 |
| 新增账目 | 通过 | `POST /api/transactions` 返回 `201 Created`。 |
| 编辑账目 | 通过 | `PUT /api/transactions/{id}` 将金额改为 `4000` 分并返回更新后记录。 |
| 删除/撤销 | 通过 | `DELETE /api/transactions/{id}` 返回撤销地址；`POST /api/transactions/{id}/restore` 后 `deleted_at=null`。 |
| 首页统计 | 通过 | 新增、编辑、恢复后 `GET /api/summary` 返回更新后的整数分统计。 |
| SQLite 备份 | 通过 | `GET /api/backup` 返回 `application/vnd.sqlite3`，文件名 `smart-ledger-backup-YYYYMMDD-HHMMSS.sqlite`，下载内容 20480 字节。 |
| Backend 自动测试 | 通过 | `25 passed, 2 warnings`。新增 1 个 `工资到账8000` 回归用例。 |
| Backend 语法检查 | 通过 | `uv run --no-project python -m py_compile backend/main.py backend/test_main.py` 通过。 |
| Frontend typecheck | 通过 | `npm run typecheck` 通过。 |
| Frontend build | 通过 | 沙箱内因 esbuild 目录权限失败；受控放行环境下 `npm run build` 通过。 |

## 4. Warning 与环境说明

- `StarletteDeprecationWarning` 仍存在，属于 Review 报告中的建议优化范围，本轮不处理。
- Backend 测试本次另出现 `PytestCacheWarning`，原因是当前运行环境写 `.pytest_cache` 受限；测试本身 25 项全部通过，不属于产品代码问题。
- `git status` 仍提示无法访问 `C:\Users\冯志贡/.config/git/ignore`，这是本机 Git 全局 ignore 权限问题，不是 Smart Ledger 业务代码问题。
- 前端 build 在普通沙箱内因 esbuild 读取上级目录权限失败；同一命令在受控放行环境通过，判断为当前沙箱权限限制。

## 5. 是否引入新问题

本轮未发现新的交付阻塞问题。

注意事项：

- `tmp-review-fix/` 是本轮临时验证目录，已加入 `.gitignore`。
- 本轮没有修改 API 契约、数据模型、正式分类 code 或 V1 功能范围。
- 本轮没有删除或清空正式 SQLite 数据库。

## 6. 本轮未处理的建议优化

Review 报告中的 4 个建议优化本轮明确不处理：

1. S-1：统一 `8000工资` 的规则文档和运行口径的更广泛文档维护。
2. S-2：补充更多边界测试。
3. S-3：处理 Starlette 测试依赖告警。
4. S-4：完整更新项目进度文档到最终 Review 状态之外的后续交付状态。

其中 `工资到账8000` 回归测试属于 G-3 必需修复，不代表本轮已经处理完整的建议优化清单。

## 7. 当前结论

Review 报告中的 4 个一般问题已经完成最小修复，并完成主 Agent 回归验证。当前项目状态应标记为：

`Review 问题修复完成 / 待回归测试`

本报告不代表 V1 最终交付完成；是否进入最终交付确认，应等待用户下一步指令。

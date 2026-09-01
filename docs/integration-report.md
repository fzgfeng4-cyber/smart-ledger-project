# Smart Ledger V1 前后端联调报告

## 1. 文档定位

- 阶段：第 8 步，主 Agent 前后端联调。
- 日期：2026-08-30。
- 范围：只验证已经冻结的 V1 前端、后端、API 契约和 SQLite 真实链路。
- 明确不做：不进入 Test Agent，不进入 Review Agent，不扩展 V1 功能，不加入微信/支付宝、OCR、通知、登录、云同步、AI 大模型、复杂报表或 PWA。

## 2. 本轮最小修改

本轮只做了真实联调所必需的前端运行模式修复：

| 文件 | 修改内容 |
| --- | --- |
| `frontend/src/api.ts` | 默认使用真实 Backend：`http://127.0.0.1:8000`；只有显式设置 `VITE_USE_MOCK=true` 时才启用 mock。 |
| `frontend/src/pages/HomePage.vue` | mock 提示只在真正使用 mock API 时显示，正式运行不再提示“当前使用前端 mock API”。 |

没有修改 `docs/api-contract.md`，没有修改数据模型、分类规则或 UI 方案，没有新增 V1 之外功能。

## 3. 运行环境和启动结果

### 3.1 环境

| 项目 | 实测结果 |
| --- | --- |
| Node.js | `v24.16.0` |
| npm | `11.13.0` |
| Python | 系统 PATH 中没有 `python` / `py`；通过 `uv --python 3.13` 使用 Python `3.13.13` |
| 后端依赖 | 通过 `uv` 安装/解析 FastAPI、uvicorn、pytest、httpx |
| 前端依赖 | `frontend/node_modules` 已存在 |

### 3.2 环境限制

| 现象 | 判断 | 处理 |
| --- | --- | --- |
| `uv` 默认缓存目录 `AppData\Local\uv\cache` 权限不足 | 当前运行环境配置问题，不是后端代码问题 | 改用项目内 `.uv-cache` |
| 首次 PyPI 访问被沙箱网络限制拦截 | 当前运行环境限制 | 按规则请求放行后成功 |
| pytest 默认临时目录 `AppData\Local\Temp\pytest-of-*` 权限不足 | 当前运行环境配置问题，不是测试代码问题 | 使用 `--basetemp .pytest-tmp` 重跑 |
| Vite/esbuild 在沙箱内读取 `vite.config.ts` 时报 `Access is denied` | 当前运行环境限制，不是前端代码问题 | 按规则用正常权限运行 `npm run build` 和 `npm run dev` |
| Chrome headless/CDP 无法保持 DevTools 端口，`--dump-dom` 无输出 | 当前浏览器自动化通道限制 | 不引入新依赖；浏览器 UI 自动点击未完成，改用真实 API、Vite 页面加载、CORS 和后端日志验证 |

### 3.3 服务启动

| 服务 | 地址 | 结果 |
| --- | --- | --- |
| Backend | `http://127.0.0.1:8000` | 正常启动，Uvicorn 无启动错误 |
| Frontend | `http://127.0.0.1:5173` | 正常启动，Vite dev server 无启动错误 |

Backend 日志显示前端页面加载后触发了真实跨端口请求，包括：

- `OPTIONS /api/categories`
- `GET /api/categories`
- `OPTIONS /api/summary`
- `GET /api/summary`
- `OPTIONS /api/transactions?page=1&page_size=5`
- `GET /api/transactions?page=1&page_size=5`

CORS 预检实测：

- `OPTIONS /api/parse` 返回 `200`
- `access-control-allow-origin` 返回 `http://127.0.0.1:5173`
- `access-control-allow-methods` 包含 `GET, POST, PUT, DELETE, OPTIONS`

## 4. API 契约一致性检查

后端已实现 `docs/api-contract.md` 冻结的全部 V1 API：

- `POST /api/parse`
- `GET /api/categories`
- `POST /api/transactions`
- `GET /api/transactions`
- `GET /api/transactions/{id}`
- `PUT /api/transactions/{id}`
- `DELETE /api/transactions/{id}`
- `POST /api/transactions/{id}/restore`
- `GET /api/summary`
- `GET /api/backup`

前端统一通过 `frontend/src/api.ts` 调用这些 API。字段仍为 `snake_case`，分类 code、错误格式和请求路径没有发现需要修改契约的问题。

## 5. 解析联调结果

以下请求均打到真实 Backend，不使用 mock：

| 输入 | amount_cents | type | category | note | original_text |
| --- | ---: | --- | --- | --- | --- |
| `5块买菜` | 500 | expense | groceries_food | 买菜 | `5块买菜` |
| `18块吃面` | 1800 | expense | dining | 吃面 | `18块吃面` |
| `300加油` | 30000 | expense | vehicle_fuel | 加油 | `300加油` |
| `20打车` | 2000 | expense | transportation | 打车 | `20打车` |
| `8000工资` | 800000 | income | salary | 工资 | `8000工资` |
| `昨天买菜35` | 3500 | expense | groceries_food | 买菜 | `昨天买菜35` |
| `今天午饭15块` | 1500 | expense | dining | 午饭 | `今天午饭15块` |
| `带孩子吃饭86` | 8600 | expense | dining | 带孩子吃饭 | `带孩子吃饭86` |

异常输入实测：

| 输入 | 结果 |
| --- | --- |
| `35` | `needs_input`；只识别金额 `3500`，`type` 和 `category` 为 `null`，不默认支出 |
| `买菜` | `needs_input`；提示缺少 `amount_cents`，保留支出和买菜/食品建议 |
| `买菜35又打车20` | `needs_input`；`amount_cents = null`，返回 `MULTIPLE_AMOUNTS`，不自动拆两笔 |
| 空输入 | `no_draft`；不生成草稿 |

## 6. 真实记账链路

已用真实 Backend 跑通：

1. 解析 `35块买菜`。
2. 用户确认等价请求 `POST /api/transactions`。
3. 后端返回 `201`。
4. `GET /api/transactions/{id}` 能读取该账目。
5. `GET /api/transactions` 能在列表中看到该账目。
6. `GET /api/summary` 的今天支出和本月支出随保存更新。
7. 直接查询 SQLite 文件能看到对应记录。

手动补全流程也已验证：

- 解析 `35` 后，补充 `type = expense`、`category = groceries_food`、`note = 买菜` 并保存成功。
- 保存后的 `original_text` 仍为 `35`，没有被补全字段覆盖。

## 7. 编辑、删除、撤销和重复提醒

### 7.1 编辑

已将一笔 `35块买菜` 从 `3500` 分改为 `4000` 分：

- `PUT /api/transactions/{id}` 返回 `200`。
- `created_at` 保持不变。
- `updated_at` 已更新。
- 刷新式重新读取详情后仍显示新金额。

### 7.2 删除和撤销

已验证两种情况：

- 删除后不撤销：`DELETE /api/transactions/{id}` 返回 `200`，随后 `GET /api/transactions/{id}` 返回 `404`，列表隐藏该账。
- 删除后 10 秒内撤销：`POST /api/transactions/{id}/restore` 返回 `200`，`deleted_at` 恢复为 `null`，详情重新可见。

### 7.3 未来日期

输入 `12月20日买菜35` 时：

- 解析结果包含 `FUTURE_DATE`。
- 尝试直接保存返回 `400 VALIDATION_ERROR`。
- 符合“未来日期改成今天或过去日期前不能保存”的 V1 决策。

### 7.4 重复提醒

连续保存相同业务字段的 `35块买菜`：

- 未传 `confirm_duplicate` 时返回 `200`、`duplicate_warning = true`、`transaction = null`。
- 再传 `confirm_duplicate = true` 后返回 `201`，允许保存真实重复账。

## 8. SQLite 验证

真实数据库文件：

```text
backend/data/smart-ledger.sqlite
```

直接查询结果：

| 指标 | 数值 |
| --- | ---: |
| 文件大小 | 12288 bytes |
| 总记录数 | 7 |
| 有效记录数 | 6 |
| 软删除记录数 | 1 |

已确认记录中包含：

- `35块买菜` 保存为 `amount_cents = 4000`、`type = expense`、`category = groceries_food`
- 手动补全的 `35` 保存为 `original_text = 35`
- `8000工资` 保存为 `type = income`、`category = salary`
- 删除未撤销的 `20打车` 保留 `deleted_at`

这证明数据已经真实写入 SQLite，不是前端 mock 或内存状态。

## 9. 备份验证

已调用：

```text
GET /api/backup
```

实测结果：

| 项目 | 结果 |
| --- | --- |
| HTTP 状态 | `200` |
| Content-Type | `application/vnd.sqlite3` |
| 文件名 | `smart-ledger-backup-20260830-060446.sqlite` |
| 文件大小 | 12288 bytes |
| SQLite 文件头 | 通过 |
| `transactions` 表 | 存在 |
| 备份内总记录数 | 7 |
| 备份内有效记录数 | 6 |

备份是完整 SQLite 文件下载，没有引入恢复、云同步、自动备份或导入功能。

## 10. 自动检查结果

| 检查 | 结果 |
| --- | --- |
| 后端 Python 语法检查 | 通过 |
| 后端自动测试 | `24 passed, 1 warning` |
| 前端 TypeScript 检查 | 通过 |
| 前端生产构建 | 通过 |
| 后端启动检查 | 通过 |
| 前端启动检查 | 通过 |

后端测试中的 1 个 warning 来自 FastAPI/TestClient 依赖链的 `StarletteDeprecationWarning`，不影响当前 V1 功能通过。

## 11. 浏览器验证边界

已验证：

- 前端页面地址 `http://127.0.0.1:5173/` 返回 `200`。
- Vite 入口脚本 `/src/main.ts` 返回 `200`，Content-Type 为 `text/javascript`。
- 后端日志出现浏览器跨端口预检和页面加载后的真实 API 请求。
- CORS 允许 `http://127.0.0.1:5173` 调用 `http://127.0.0.1:8000`。

未完全自动化验证：

- 由于当前环境没有可用的 Playwright/Puppeteer，Chrome headless/CDP 也无法保持调试端口，本轮未能用自动浏览器脚本完成“在页面输入、点击确认、点击删除/撤销”的 UI 操作。
- 这属于当前运行环境限制，不是已发现的前端或后端代码问题。
- 第 9 步 Test Agent 可以在可用浏览器环境下补做 UI 级端到端测试；当前不阻塞进入独立测试阶段。

## 12. 联调结论

第 8 步主 Agent 前后端联调通过：

- 前端正式运行模式已从 mock 切到真实 Backend。
- API 契约未发现阻塞问题。
- Vue 依赖的真实 Backend API、FastAPI、SQLite 写入、查询、编辑、软删除、撤销、统计和备份均已验证。
- 自动测试和前端构建均通过。
- 当前不标记 V1 最终交付；下一步应进入 Test Agent 独立测试。

# Smart Ledger V1 技术方案调研

- 研究日期：2026-08-29
- 研究对象：Smart Ledger V1，一句话记账的本地单用户闭环
- 依据文档：`PROJECT.md`、`docs/product-v1.md`
- 本文件所有权：Research Agent，仅修改本文件
- 研究范围：应用形态、前后端、存储、解析/AI、日期、本地运行、隐私安全和未来扩展
- 明确不做：不创建 `frontend/`、`backend/`，不写业务代码，不进入 Data、Classification、UX/UI 或实现阶段

## 结论先行

V1 推荐采用普通本地 Web App：浏览器访问本机回环地址，后端进程在本机提供页面和 API，账单保存到本机 SQLite 文件。前端推荐 Vue 3 + TypeScript + Vite，后端推荐 Python 3 + FastAPI，分类和字段识别继续采用规则、关键词和正则表达式，不把云端大模型作为可用前提。

这个结论不是为了证明初步方案一定正确，而是按“纯新手容易开发、容易运行、容易调试、容易理解，能够长期自用，并保留未来扩展空间”的顺序比较后的结果。PWA、APK、浏览器数据库和大模型都可以作为后续选项，但都不是 V1 闭环的必要条件。

## 研究方法与证据边界

本轮优先查阅 Vue、React、FastAPI、Python、Node.js、SQLite、MDN、Android Developers、Tauri、Electron、OWASP 和 Microsoft 的公开文档。当前环境未提供本技能要求的 Firecrawl/Exa MCP，仅使用可用的网页搜索和页面打开能力；关键事实均在正文中给出直链。

- **官方事实**：可以由链接直接核对的 API、工具能力、运行约束或安全说明。
- **工程判断**：结合本项目范围和新手优先级作出的取舍，不等同于公开 benchmark。
- **未验证**：本项目没有实际语料集、性能测试、准确率测试、成本测试或当前机器环境验证，不能写成确定数字。

## 1. 应用形式比较

### 1.1 普通本地 Web App

方案是：前端构建为静态文件，后端在本机启动，用户用浏览器访问 `http://127.0.0.1:<端口>`。FastAPI 官方文档展示了在 `127.0.0.1` 启动服务、通过浏览器访问以及使用自动 API 文档的完整路径；FastAPI 也提供静态文件和前端构建产物托管方式（[FastAPI First Steps](https://fastapi.tiangolo.com/tutorial/first-steps/)、[FastAPI Frontend](https://fastapi.tiangolo.com/tutorial/frontend/)、[FastAPI Static Files](https://fastapi.tiangolo.com/tutorial/static-files/)）。

对 V1 的意义：浏览器负责界面，FastAPI 负责规则解析、字段校验、SQLite CRUD 和汇总；不用账号、不用外部服务、不用 APK 构建链。缺点是后台进程必须运行，关闭服务后页面无法访问数据库。

### 1.2 PWA

PWA 是在 Web App 上增加可安装的应用外壳。MDN 说明，PWA 安装通常需要 manifest，并且安装页面应来自 HTTPS、`localhost` 或 `127.0.0.1`；Service Worker 常用于缓存和离线体验，但并非安装本身的全部条件（[MDN：Making PWAs installable](https://developer.mozilla.org/en-US/docs/Web/Progressive_web_apps/Guides/Making_PWAs_installable)）。Service Worker 有独立生命周期、由浏览器启动和终止，也不能直接替代一个本机 SQLite 服务（[MDN：Service Worker API](https://developer.mozilla.org/en-US/docs/Web/API/Service_Worker_API)、[web.dev：Service workers](https://web.dev/learn/pwa/service-workers/)）。

PWA 能改善“有图标、独立窗口、以后缓存前端资源”的体验，但不能自动解决 V1 的后端进程、SQLite 文件访问和数据备份问题。若以后要做到后端停止后仍能完整记账，就必须把账单写入 IndexedDB，或把后端一起封装，届时已是架构变化。

### 1.3 原生 Android App / APK

原生 Android 可提供手机端体验、通知监听、相机、后台任务和应用商店分发。Android 官方当前以 Jetpack Compose 作为现代原生 UI 工具包，使用 Kotlin 和 Android Studio 形成另一套构建、调试、测试和发布链（[Android Developers：Android is Compose-first](https://developer.android.com/develop/ui/compose/first)）。后续若研究通知采集，官方 `NotificationListenerService` 还要求声明专用权限和服务配置（[Android Developers：NotificationListenerService](https://developer.android.com/reference/android/service/notification/NotificationListenerService)）。

V1 没有手机通知、截图、相机、后台采集或应用商店要求；直接做 APK 会引入 Kotlin/Android Studio、设备兼容、权限和第二套 UI 代码。**V1 没有必要直接做 APK。**

### 1.4 桌面封装：Tauri / Electron

这是将 Web UI 封装成桌面窗口的方案。Tauri 支持多种前端，并把前端作为静态 Web 资源提供，但仍要求理解桌面封装、原生绑定和构建依赖（[Tauri：What is Tauri?](https://tauri.app/start/)、[Tauri：Frontend Configuration](https://tauri.app/start/frontend/)）。Electron 使用主进程、渲染进程和预加载脚本等多进程模型，能提供桌面能力，但相应的安全和运行模型也更复杂（[Electron：Process Model](https://www.electronjs.org/docs/latest/tutorial/process-model)）。

V1 只需要浏览器和本机服务，桌面壳不能减少规则、数据库或业务测试工作。未来若用户明确需要单文件安装、托盘或系统级快捷入口，可以在 Web 版本稳定后再评估。

### 1.5 结论

| 应用形式 | V1 开发/运行判断 | 结论 |
| --- | --- | --- |
| 普通本地 Web App | 结构直观，浏览器和后端日志都容易调试；需要本机服务运行 | **推荐** |
| PWA | 可安装、可缓存，但增加 manifest、Service Worker 生命周期和离线一致性问题；不自动替代 SQLite 后端 | V1 不做，保留兼容空间 |
| 原生 Android APK | 手机能力强，但引入 Kotlin、Android Studio、权限、设备测试和第二套代码 | V1 不做 |
| Tauri/Electron | 可做桌面安装包，但增加桌面壳、打包和安全模型 | V1 不做 |

## 2. 前端技术比较

### 2.1 候选方案

| 方案 | 优点 | 对 V1 的主要代价 | 工程判断 |
| --- | --- | --- | --- |
| 原生 HTML/CSS/JavaScript | 无 UI 框架；标准能力直接；初始文件少 | 输入、确认、编辑、删除、撤销、列表和汇总的状态需要手工组织，页面增长后容易出现 DOM 和状态不同步 | 最初演示最简单，长期维护不优 |
| React | 组件和状态模型成熟；官方文档覆盖状态组织和组件协作 | 新项目需要额外选择框架或 Vite、路由、数据请求和状态组织；React 官方已弃用 Create React App，并建议新项目使用框架或自行配合构建工具（[React：Sunsetting Create React App](https://react.dev/blog/2025/02/14/sunsetting-create-react-app)、[React：Creating a React App](https://react.dev/learn/creating-a-react-app)） | 可用，但选择项比 V1 所需更多 |
| React + TypeScript | 在 React 组件和 API 数据之间增加静态类型检查，便于重构；TypeScript 官方将其定位为 JavaScript 的静态类型检查器（[TypeScript Documentation](https://www.typescriptlang.org/docs/)、[TypeScript Handbook](https://www.typescriptlang.org/docs/handbook/intro.html)） | 同时学习 JSX、React 状态、TypeScript 类型和额外工具链；若仍采用 React，需要先决定框架或 Vite | 适合已有 React 基础的团队，不是本项目新手的最低复杂度 |
| Vue 3 + TypeScript | Vue 建立在 HTML、CSS、JavaScript 之上，提供声明式渲染、响应式和组件模型；官方提供 Vue 3 + Vite + TypeScript 脚手架，且有一等 TypeScript 支持（[Vue Introduction](https://vuejs.org/guide/introduction)、[Vue with TypeScript](https://vuejs.org/guide/typescript/overview)） | 仍需学习 TypeScript、单文件组件和构建工具；Vite 本身不会自动完成类型检查，需要配合 `vue-tsc` 或 IDE | 对本项目的表单、确认页、列表和状态切换更容易形成清晰组件边界 |
| Svelte/SvelteKit | Svelte 官方定位为编译型 UI 框架，组件写法简洁（[Svelte](https://svelte.dev/)） | V1 不需要 SvelteKit 的服务端能力；团队需要额外熟悉一套生态，收益不足以抵消迁移和学习成本 | 值得知道，但不作为 V1 方案 |

### 2.2 推荐

**V1 推荐 Vue 3 + TypeScript + Vite。**

理由是：

1. Vue 官方仍保留渐进式使用方式，文档明确说明可以从标准 HTML、CSS、JavaScript 逐步进入组件化应用；这更符合纯新手的学习路径。
2. Vue 官方脚手架直接提供 Vite 和 TypeScript 组合，避免手工拼装构建工具。
3. V1 已经不是一个只有一个输入框的静态页面，而是至少包含输入、识别结果、确认、编辑、删除、撤销和首页汇总多个状态。组件和响应式状态能减少手工 DOM 同步。
4. V1 不需要 Nuxt、SSR、复杂状态管理库或 UI 大组件库。先用 Vue 内置能力保持依赖少，未来需要时再增加路由或状态库。

这是工程判断，不是“Vue 在所有项目都优于 React”的结论。若主 Agent 或 Frontend Agent 已有明确 React 能力，React + TypeScript + Vite 也可以工作，但会改变本研究对“纯新手最低理解成本”的推荐，不应同时混用两套方案。

## 3. 后端技术比较

### 3.1 Python + FastAPI

FastAPI 官方以 Python 类型标注为基础，提供输入校验、OpenAPI、Swagger UI 和 ReDoc 自动文档；官方示例还展示了本地服务、自动文档和 `GET/POST/PUT/DELETE` 路由（[FastAPI Features](https://fastapi.tiangolo.com/features/)、[FastAPI First Steps](https://fastapi.tiangolo.com/tutorial/first-steps/)）。Python 文档提供 `sqlite3` 数据库接口，可通过 SQL 访问 SQLite 文件（[Python sqlite3](https://docs.python.org/3/library/sqlite3.html)）。

优点是 API 契约、字段校验和手工调试入口集中，错误更容易在后端边界暴露；未来导入或 OCR 的处理流程也有清晰的服务层位置。缺点是前端和后端分别使用 TypeScript 与 Python，开发者需要理解两种语言和本地 Python 环境。后一个缺点是真实存在，不能用“未来 OCR”强行掩盖；本次选择的首要理由是 V1 的校验和调试能力。

### 3.2 Node.js + Express

Express 官方强调灵活、不预设目录结构，也明确说明 Express 本身不包含数据库模型，数据库能力交给第三方 Node 模块（[Express FAQ](https://expressjs.com/en/5x/starter/faq/)）。如果前后端都用 JavaScript/TypeScript，语言数量较少，这是它对纯新手的实际优势。

但 V1 仍要额外决定请求校验、API 文档、数据库访问封装、错误格式和项目结构。Node.js 当前 `node:sqlite` 文档显示该模块在当前文档版本仍为 Release Candidate，且 API 版本历史较新（[Node.js SQLite](https://nodejs.org/api/sqlite.html)）；因此不能把它当作无需第三方依赖、已经完全稳定的 V1 前提。使用 Express 并非错误，但需要更多自行组装。

### 3.3 其他简单后端

Flask、Bottle 或 Python 内置 HTTP 服务可以减少框架表面，但 V1 仍需要自行补齐请求校验、错误格式、API 文档、静态前端托管约定和测试边界。Django、NestJS、全栈 React 框架等能力明显超出本地单用户 V1 的需要。它们没有带来足够的 V1 价值，所以不作为候选主路线。

### 3.4 推荐

**V1 推荐 Python 3 + FastAPI，并优先使用 Python 的 `sqlite3` 接口。**

推荐依据：FastAPI 的类型校验和自动文档能直接服务确认页、字段校验和联调；FastAPI 可以在同一个本地服务中托管构建后的前端；SQLite 不需要另行运行数据库服务器。日常使用可以只启动一个 Python 服务，开发时再按需要运行 Vite。

如果主 Agent 的首要目标改为“前后端必须同一种语言”，Node.js + Express 才值得重新评估；在当前产品边界和新手优先级未改变时，不改变本推荐。

## 4. 数据库存储比较

### 4.1 localStorage

MDN 将 Web Storage 描述为按来源隔离的键值存储；`localStorage` 在浏览器关闭后通常仍保留，但其读写是同步的，会阻塞 JavaScript；隐私浏览模式下数据可能在关闭后被删除（[MDN：Web Storage API](https://developer.mozilla.org/en-US/docs/Web/API/Web_Storage_API)）。

它适合保存少量界面偏好、临时草稿或最近一次输入，不适合作为长期账单主数据库。账单列表、按日期汇总、编辑、删除、撤销以及未来导入都会让“一个 JSON 字符串”变成难以维护的手工数据层。

### 4.2 IndexedDB

MDN 将 IndexedDB 定义为浏览器内的异步结构化数据库，支持对象、索引和事务，适合较大的结构化数据；同时它按来源隔离，浏览器的存储配额和回收策略会因浏览器而异（[MDN：IndexedDB API](https://developer.mozilla.org/en-US/docs/Web/API/IndexedDB_API)、[MDN：Using IndexedDB](https://developer.mozilla.org/en-US/docs/Web/API/IndexedDB_API/Using_IndexedDB)）。

IndexedDB 是纯浏览器离线应用的合理选择，但它会把数据库、规则解析和备份逻辑都放到前端，还增加异步事务、版本升级和浏览器数据生命周期问题。若 V1 继续采用 FastAPI 后端，前端再同时维护 IndexedDB 和 SQLite 会产生两个数据真相源，不推荐。

### 4.3 SQLite

SQLite 官方说明它直接读写磁盘数据库文件，不需要独立数据库服务器，因此是 serverless 和 zero-configuration 的数据库；官方也建议低并发、设备本地、数据量可控的场景优先考虑 SQLite（[SQLite Is Serverless](https://www.sqlite.org/serverless.html)、[SQLite Zero-Configuration](https://www.sqlite.org/zeroconf.html)、[Appropriate Uses For SQLite](https://www.sqlite.org/whentouse.html)）。

SQLite 的边界也要说清楚：一个数据库文件同一时刻只能有一个写者，跨多台机器通过网络文件系统共享不是合适场景（[SQLite FAQ](https://sqlite.org/faq.html)）。这不影响 V1 的本机单用户使用。SQLite 使用灵活类型，不能只依赖声明类型保证输入正确；金额、日期、收支和分类仍需要后端校验或明确的数据库约束（[SQLite Datatypes](https://www.sqlite.org/datatype3.html)）。

### 4.4 JSON/CSV 文件和云数据库

单个 JSON 文件初期看起来最简单，但查询、事务、并发写入、修改失败恢复和未来迁移都需要自行设计。CSV 更适合作为交换或导出格式，不适合直接承担账单数据库。PostgreSQL、MySQL 或云数据库适合多用户、远程访问和较高并发，但 V1 明确不做账号、云同步和远程服务。

### 4.5 推荐

**V1 推荐后端 SQLite 文件作为唯一账单存储，前端不把 localStorage 或 IndexedDB 当作账单主库。**

具体边界：数据库放在稳定的应用数据目录，不放进前端构建产物或 Git 工作区；所有写入经过后端 API；V1 只实现产品已经确认的字段和分类，不提前加入商户、支付来源或导入字段。未来扩展可以通过迁移增加字段或表，但这不授权当前 Agent 进入 Data 阶段。

## 5. 一句话记账是否需要真正 AI

### 5.1 三种方案比较

下面是针对当前固定分类、固定字段、单笔输入、确认后保存的工程比较。本轮未找到足够的公开统一中文记账 benchmark，本项目也没有实际语料测试，因此“准确率”和“成本”不能写成数字，具体结果均为相对判断或未验证。

| 方案 | 准确率与覆盖 | 成本 | 网络依赖 | 速度 | 隐私 | 维护 | 新手难度 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| A. 规则 + 关键词 + 正则 | 对已定义样例和边界可做到稳定、可解释；对未覆盖表达的覆盖有限 | 无按调用计费 | 无 | 本地处理，延迟可控 | 原句留在本机 | 增加词表、规则和测试 | 低 |
| B. 全部交给大模型 | 语言覆盖潜力较大，但输出受模型、提示词和服务变化影响；实际准确率未验证 | 依服务商、模型和调用量而变，未验证 | 云端模型通常需要网络；本地模型需要额外运行环境 | 受网络、排队和模型大小影响，未验证 | 云端方案可能把原句发送到外部；具体保留策略未验证 | 需要维护 API、提示词、解析兜底和费用 | 高 |
| C. 规则优先，失败再 AI | 规则路径稳定，失败输入有更高覆盖潜力；整体准确率和召回率未验证 | 只有失败请求可能产生费用，但仍未验证 | 正常规则无需网络，触发 AI 时需要网络或本地模型 | 正常输入快，失败输入变慢 | 只有在明确触发时才可能外发，但仍需用户同意和供应商审查 | 同时维护规则、模型、超时、失败回退和可重复测试 | 中高 |

### 5.2 V1 推荐

**V1 采用 A：规则、关键词、正则优先，不接入真正 AI。**

这不是否定 AI，而是 V1 的字段和分类足够有限，且产品要求结果必须确认、可解释、可修改、无需联网。规则失败时应保留原句，把不确定字段标为待确认或使用明确标记的兜底分类；不能为了“看起来智能”而静默猜测。

C 可以作为未来可选能力，但必须满足：用户明确同意、界面明确提示文本可能离开本机、失败和超时不影响本地记账、模型结果仍经过确认页、规则结果优先且可追溯。B 不适合作为 V1 可用前提。

## 6. 日期识别范围

日期规则是 V1 的产品技术约定，不是复杂自然语言理解任务。建议支持以下最小集合：

| 输入形式 | V1 建议行为 |
| --- | --- |
| 没有日期 | 使用保存时的本机当前日期，默认今天 |
| `今天` | 当前本机日期 |
| `昨天` | 当前本机日期减一天 |
| `8月20号`、`8月20日` | 按当前年份解释；先校验真实日历日期，再进入确认页 |
| `2026年8月20日`、`2026-08-20` | 按明确年份解释；校验真实日期，再进入确认页 |
| 日期字段手工选择 | 允许今天和有效历史日期；与产品规则一致，不允许未来账单 |

若 `8月20号` 按当前年份解释后变成未来日期，不要擅自改成上一年；应提示用户补充年份或在确认页修改。`明天`、`下周一`、`上个月`、日期范围、时间点、农历、中文数字日期和含糊的“几号”建议后置。`前天`虽然规则简单，但产品当前没有要求，V1 不因它扩展范围。

实现时需要让浏览器和后端使用同一个本机时区及日期语义，避免跨午夜时一个页面显示今天、后端却保存昨天。具体日期字段类型和测试边界由 Data Agent 与主 Agent 决定，本报告不定义数据表。

## 7. 本地使用方式

### 7.1 普通用户的目标使用方式

日常使用不应要求用户每次手工打开多个终端。推荐提供一个 Windows 可点击启动入口，流程如下：

1. 启动入口检查本地运行环境和端口。
2. 启动 FastAPI 本地服务，并只监听 `127.0.0.1`。
3. 等待一个简单健康检查成功。
4. 自动打开浏览器到本地 URL。
5. 保留一个可查看日志的窗口，便于新手遇到问题时知道服务是否启动；后续稳定后再考虑隐藏窗口。

双击脚本自动启动服务并打开浏览器在 Windows 上是可行的，但属于运行包装，不是另一个后端架构。V1 开发期间仍可使用终端运行服务；普通用户路径应以点击入口为目标。若服务已经在运行，入口应复用或给出明确提示，不能重复启动多个进程争抢 SQLite 文件。

开发时可以让 Vite 提供热更新前端、FastAPI 提供 API；日常使用时先构建前端，再由 FastAPI 托管静态产物，这样用户只需要一个后端进程。FastAPI 官方文档已经说明静态前端构建产物可以由 FastAPI 提供（[FastAPI Frontend](https://fastapi.tiangolo.com/tutorial/frontend/)）。

### 7.2 PWA 的未来可能性

未来可以在同一套前端上增加 manifest 和 Service Worker。`localhost` 与 `127.0.0.1` 被浏览器视为适合本地开发和 Service Worker 的安全来源，但 PWA 安装和浏览器支持仍然因平台而异（[MDN：Secure Contexts](https://developer.mozilla.org/en-US/docs/Web/Security/Secure_Contexts)、[MDN：Making PWAs installable](https://developer.mozilla.org/en-US/docs/Web/Progressive_web_apps/Guides/Making_PWAs_installable)）。

需要明确：安装 PWA 图标不等于本地后端一直运行，也不等于数据库自动同步。PWA 先作为前端壳和启动体验的增强项，是否做完整离线记账要等未来重新决定存储架构。

## 8. 隐私和安全

V1 不需要企业级认证、密钥管理、远程审计或复杂权限系统，但账单属于个人财务信息，以下措施是必要的。

| 风险/问题 | V1 最小措施 | 是否进入 V1 |
| --- | --- | --- |
| 外部访问 | 后端只绑定 `127.0.0.1`，不默认监听 `0.0.0.0`；不做云端 API、账号、登录和统计脚本 | 必须 |
| 开发跨端口 | 若 Vite 和 FastAPI 开发时是不同 origin，只允许明确的本地 origin；不要用宽泛的 CORS 通配。FastAPI 文档说明 origin 包含协议、主机和端口，并建议显式允许列表（[FastAPI CORS](https://fastapi.tiangolo.com/tutorial/cors/)） | 必须 |
| 用户原句和备注 | 前端按普通文本渲染，不把用户输入当 Vue 模板或未经处理的 HTML；Vue 官方说明模板内容必须可信，普通插值会自动转义（[Vue Security](https://vuejs.org/guide/best-practices/security)） | 必须 |
| API 和数据库输入 | 后端重复校验金额、收支、分类和日期；SQL 使用参数绑定/预编译语句，不拼接用户输入。OWASP 将参数化查询列为主要防护方式（[OWASP SQL Injection Prevention](https://cheatsheetseries.owasp.org/cheatsheets/SQL_Injection_Prevention_Cheat_Sheet.html)） | 必须 |
| 数据文件暴露 | SQLite 文件放在应用数据目录，不提交 Git，不打包进前端；依赖 Windows 用户账户和文件权限 | 必须 |
| 应用级加密 | V1 不自行实现 SQLite 加密和密码解锁，避免密钥丢失导致账单不可恢复；如果设备需要整盘保护，使用操作系统已有能力。当前机器是否启用 BitLocker 未验证（[Microsoft：BitLocker overview](https://learn.microsoft.com/en-us/windows/security/operating-system-security/data-protection/bitlocker/)） | V1 不做 |
| 备份 | 至少保持数据库路径稳定，方便用户复制；运行中直接复制文件有一致性风险，SQLite 提供 Online Backup API 处理活动数据库备份（[SQLite Backup API](https://www.sqlite.org/backup.html)） | 最小保护必须有；按钮待决策 |
| 导出/恢复 | 用户可恢复比“只有数据库文件”更易用。JSON/CSV 导出不等于 V2 导入，是否将导出按钮纳入 V1 由主 Agent 决定 | 待决策 |

V1 的隐私承诺应写成可验证的行为：数据默认只写本机 SQLite，不调用云端模型，不上传账单，不需要账号。若未来增加 AI、云备份或手机采集，必须重新给出数据去向、授权、失败和撤销说明，不能沿用“本地应用”的默认印象。

## 9. 后续扩展空间

推荐路线对未来有扩展空间，但“可以扩展”不等于本轮实现或提前加字段。

| 未来版本 | 扩展判断 | 建议的边界 |
| --- | --- | --- |
| V2 账单文件导入 | 适合在后端增加文件解析适配器；SQLite 适合保存导入后的结构化账单 | 导入结果先转成待确认草稿，仍走同一确认流程；当前不实现 CSV/Excel 导入 |
| V3 OCR | 可以把 OCR 结果接入现有金额、日期、分类和备注解析链；Python 服务层便于放置后续图像处理依赖，但具体 OCR 库和准确率未验证 | OCR 只产生建议，不直接写入；当前不实现 OCR 或截图识别 |
| V4 合法半自动采集 | 研究空间存在，但普通 Web App 不能直接获得手机通知等系统能力；Android 官方通知监听需要专用权限和服务配置（[NotificationListenerService](https://developer.android.com/reference/android/service/notification/NotificationListenerService)） | 先确认平台能力、用户授权、当地法规和来源条款；可能需要 Android/PWA/桌面桥接，当前不实现 |
| 未来 AI 辅助分类 | 可以保留规则分类接口，在低置信度或用户主动请求时接入可选模型 | AI 结果仍需用户确认，默认不发送原句；供应商成本、留存和本地模型性能均未验证 |

关键扩展原则是“多种输入来源，共用同一个待确认草稿和保存接口”。这样未来增加导入或 OCR 时，不必让每个来源直接改账，也不会破坏 V1 的确认不变量。

## 10. 与原初步方案的变化

| 初步方向 | 调研结论 | 变化 |
| --- | --- | --- |
| 本地 Web App | 继续采用普通本地 Web App，日常通过点击入口启动本机服务 | 不变；补充了运行和安全边界 |
| 规则 + 关键词，不强制云端大模型 | V1 明确采用规则、关键词、正则；AI 不作为可用前提 | 不变；进一步否定“全量大模型”作为 V1 依赖 |
| SQLite 候选数据库 | 继续采用后端 SQLite 文件，前端不另建账单 IndexedDB 主库 | 不变；明确了 SQLite 与浏览器存储的职责边界 |
| 前端技术未冻结 | 推荐 Vue 3 + TypeScript + Vite | 新增 V1 推荐 |
| 后端技术未冻结 | 推荐 Python 3 + FastAPI + `sqlite3` | 新增 V1 推荐 |
| 未说明 PWA/APK | PWA 作为后置安装/缓存体验，APK 不属于 V1 | 新增版本边界 |
| 未说明备份与安全 | 增加回环监听、参数化查询、输入转义、稳定数据库路径和备份决策 | 新增必要措施；没有扩展为企业安全 |

所以，**核心方向没有变化**。变化主要是把前后端落到可执行的 V1 组合，并说明 SQLite 应位于后端而不是浏览器；这些变化来自开发、调试和长期数据可维护性的需要，不是为了迎合初步结论。

## 11. 最终推荐技术栈（V1）

应用形式：普通本地 Web App，浏览器访问 `http://127.0.0.1:<端口>`，不直接做 PWA 或 APK。

前端：Vue 3 + TypeScript + Vite；V1 不引入 Nuxt、SSR、复杂状态管理或不必要的 UI 组件大包。

后端：Python 3 + FastAPI；使用类型校验、OpenAPI 文档和本地静态前端托管能力。

数据库：后端 SQLite 文件；账单主数据不放 `localStorage` 或 IndexedDB。

分类方式：规则 + 关键词 + 正则表达式；固定 V1 分类，无法确定时标记待确认或使用需确认的兜底分类。

AI：V1 不接入大模型，不把网络、API Key、调用费用或云端隐私策略作为可用前提；未来只考虑规则失败后的可选辅助。

运行方式：开发时可分开运行 Vite 和 FastAPI；日常由可点击启动入口启动 FastAPI，等待健康检查后打开浏览器，服务只监听本机回环地址。

为什么：这条路线能覆盖 V1 的输入、识别、确认、保存、列表、编辑、删除和汇总，同时让字段校验、API 调试和 SQLite 文件备份有清晰位置；运行时可以收敛为一个本地 Python 服务，数据不离开本机，未来可在同一确认接口上承接导入、OCR 或可选 AI。

为什么没有选择其他方案：PWA 增加安装和 Service Worker 复杂度但不替代后端；APK 增加第二套移动端和权限体系而 V1 没有手机系统能力需求；原生 HTML/JavaScript 在最初页面上简单但多状态 CRUD 长期更难维护；React 需要额外选择框架、路由和状态方案，且 CRA 已弃用；Express 虽能减少语言种类，但数据库、校验和文档要自行拼装，Node 内置 SQLite 当前仍是 Release Candidate；localStorage/IndexedDB 会把长期账单和浏览器数据生命周期绑在一起；全量 AI 增加网络、成本、隐私和不可重复性。

## 12. 仍需主 Agent 决定的问题

1. **是否把导出/备份按钮列入 V1 验收。** 研究建议至少保证数据库路径稳定并可安全备份；面向普通用户的 JSON/CSV 导出按钮是否进入 V1，产品文档当前尚未冻结。
2. **运行时版本和安装方式。** 需要冻结 Python 版本、Node/npm 是否只作为开发依赖、依赖安装方式、默认端口以及点击启动入口的具体形式。当前机器是否已经满足这些前置条件未验证。
3. **日期输入的最终清单。** 本报告建议今天、昨天、当前年份的 `M月D日`、带年份日期和 ISO 日期；是否接受带年份的其他格式由主 Agent 定稿。
4. **V1 是否需要保留最小 PWA 元数据。** 研究建议不做安装和 Service Worker，但可以由主 Agent 决定是否要求前端结构保持未来可加 manifest 的整洁边界。
5. **金额的内部表示和迁移策略。** 这属于 Data Agent 范围；本报告只要求后端校验，不预先决定列名或金额存储类型。

除以上问题外，不建议为了未来版本提前加入商户、来源、账号、同步、OCR、通知或 AI 设置。

## 13. 给后续 Agent 的读取建议

### 给主 Agent

先冻结第 11 节路线和第 12 节决策，再派 Data、Classification、UX/UI。把“本机回环、单进程日常运行、确认后保存、无云端 AI”作为跨 Agent 不变量；任何未来能力先记录为后置，不要由实现 Agent自行加入。

### 给 Data Agent

以 `docs/product-v1.md` 的五个用户可见字段和最终分类为边界；使用 SQLite 作为后端唯一账单主库。重点研究金额表示、日期只存日期还是带时间、同日排序、删除撤销以及数据库备份，不增加商户、来源、用户或同步字段。

### 给 Classification Agent

把规则、关键词、正则和冲突处理整理成可测试表；覆盖八个规定样例、多个金额、无金额、方向不明、无法分类、负数和日期边界。规则结果必须可解释、可修改，不调用云端模型，不把兜底分类伪装成确定结果。

### 给 UX/UI Agent

围绕输入、识别草稿、确认、保存反馈、列表、编辑、删除二次确认和撤销设计完整状态；必须让“待确认建议”和“已保存账单”视觉上不同。不要设计登录、联网状态、AI 等待、导入、OCR、复杂报表或 APK 专属入口。

### 给 Frontend Agent

按 Vue 3 + TypeScript + Vite 实现组件和状态；前端账单数据通过 FastAPI API 获取，不使用 localStorage/IndexedDB 作为主库。保留原句、识别提示、字段修改和失败提示，避免把用户输入作为 HTML 模板渲染。

### 给 Backend Agent

按 Python 3 + FastAPI 实现本地 API、服务端字段校验、SQLite CRUD、首页三个汇总和静态前端托管。使用参数化 SQL，默认只监听 `127.0.0.1`，开发跨端口时使用明确 CORS allowlist；不要加入认证、云同步、外部采集或未来版本字段。

## 14. 主要来源

### Web、前端与 PWA

- [MDN Web Storage API](https://developer.mozilla.org/en-US/docs/Web/API/Web_Storage_API)
- [MDN IndexedDB API](https://developer.mozilla.org/en-US/docs/Web/API/IndexedDB_API)
- [MDN Service Worker API](https://developer.mozilla.org/en-US/docs/Web/API/Service_Worker_API)
- [MDN Making PWAs installable](https://developer.mozilla.org/en-US/docs/Web/Progressive_web_apps/Guides/Making_PWAs_installable)
- [MDN Secure Contexts](https://developer.mozilla.org/en-US/docs/Web/Security/Secure_Contexts)
- [Vue Introduction](https://vuejs.org/guide/introduction)
- [Vue with TypeScript](https://vuejs.org/guide/typescript/overview)
- [Vue Quick Start](https://vuejs.org/guide/quick-start)
- [Vue Security](https://vuejs.org/guide/best-practices/security)
- [React Creating a React App](https://react.dev/learn/creating-a-react-app)
- [React Sunsetting Create React App](https://react.dev/blog/2025/02/14/sunsetting-create-react-app)
- [TypeScript Documentation](https://www.typescriptlang.org/docs/)
- [Vite Getting Started](https://vite.dev/guide/)

### 后端、SQLite 与安全

- [FastAPI Features](https://fastapi.tiangolo.com/features/)
- [FastAPI First Steps](https://fastapi.tiangolo.com/tutorial/first-steps/)
- [FastAPI Frontend](https://fastapi.tiangolo.com/tutorial/frontend/)
- [FastAPI CORS](https://fastapi.tiangolo.com/tutorial/cors/)
- [Python sqlite3](https://docs.python.org/3/library/sqlite3.html)
- [Express FAQ](https://expressjs.com/en/5x/starter/faq/)
- [Node.js SQLite](https://nodejs.org/api/sqlite.html)
- [SQLite Is Serverless](https://www.sqlite.org/serverless.html)
- [SQLite Zero-Configuration](https://www.sqlite.org/zeroconf.html)
- [Appropriate Uses For SQLite](https://www.sqlite.org/whentouse.html)
- [SQLite Datatypes](https://www.sqlite.org/datatype3.html)
- [SQLite Backup API](https://www.sqlite.org/backup.html)
- [SQLite Security](https://www.sqlite.org/security.html)
- [OWASP SQL Injection Prevention](https://cheatsheetseries.owasp.org/cheatsheets/SQL_Injection_Prevention_Cheat_Sheet.html)

### 原生和封装方案

- [Android is Compose-first](https://developer.android.com/develop/ui/compose/first)
- [Android NotificationListenerService](https://developer.android.com/reference/android/service/notification/NotificationListenerService)
- [Tauri What is Tauri?](https://tauri.app/start/)
- [Tauri Frontend Configuration](https://tauri.app/start/frontend/)
- [Electron Process Model](https://www.electronjs.org/docs/latest/tutorial/process-model)
- [Microsoft BitLocker overview](https://learn.microsoft.com/en-us/windows/security/operating-system-security/data-protection/bitlocker/)

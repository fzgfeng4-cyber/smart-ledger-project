# Smart Ledger

Smart Ledger 是一个面向个人长期使用的离线优先 Android 记账应用。账目、分类、预算、统计和备份主要在设备本地处理，适合个人记录日常收支。

## 当前版本

- 当前个人使用版：`v3.1.0`
- 应用版本：`3.1.0+3`
- Android `applicationId`：`com.fzgfeng4.smartledger`
- 当前开发分支：`v2-development`
- 最新发布：[Smart Ledger v3.1.0](https://github.com/fzgfeng4-cyber/smart-ledger-project/releases/tag/v3.1.0)

## 版本区分

| 版本 | 标签或分支 | 状态 | 说明 |
| --- | --- | --- | --- |
| V1 | `v1.0.0-frozen` | 冻结归档 | 初始 Android 本地记账版本 |
| V2.6 | `v2.6.0` | 历史发布版 | 增加批量记账、OCR、导入、预算和统计能力 |
| V3.1 | `v3.1.0`、`v2-development` | 当前个人使用版 | 优化新增账目确认、统计周期视图、批量自然语言记账和记账工具入口 |

旧版本标签和 Release 保留在同一仓库中，互不覆盖。`v3.1.0` 是当前推荐安装版本，`v1.0.0-frozen` 继续作为 V1 的历史冻结点。

## 主要功能

- 一句话识别金额、收支类型、分类、备注和日期，并在保存前确认。
- 支持多笔自然语言账目拆分、逐笔修改、排除、恢复和一次性保存。
- 支持本地中文 OCR 识别账单图片。
- 支持微信和支付宝 CSV 账单导入，并提供本地分类建议。
- 支持固定分类、分类搜索和预算分类选择。
- 支持账目搜索、编辑、软删除、撤销恢复和最近账目查看。
- 支持月度、年度收入与支出趋势，以及支出分类统计。
- 支持本地 SQLite 数据存储和备份恢复。

## APK 下载

v3.1.0 使用 Release 分 ABI APK。只需下载与手机 ABI 匹配的一个文件，不要同时安装多个 ABI 版本。

| 文件 | 适用设备 | 下载 |
| --- | --- | --- |
| `SmartLedger-v3.1.apk` | `arm64-v8a`，推荐大多数安卓手机 | [下载推荐版](https://github.com/fzgfeng4-cyber/smart-ledger-project/releases/download/v3.1.0/SmartLedger-v3.1.apk) |
| `SmartLedger-v3.1-armeabi-v7a.apk` | `armeabi-v7a`，较旧的 32 位 ARM 手机 | [下载 32 位版](https://github.com/fzgfeng4-cyber/smart-ledger-project/releases/download/v3.1.0/SmartLedger-v3.1-armeabi-v7a.apk) |
| `SmartLedger-v3.1-x86_64.apk` | `x86_64`，部分模拟器或 Intel Android 设备 | [下载 x86_64 版](https://github.com/fzgfeng4-cyber/smart-ledger-project/releases/download/v3.1.0/SmartLedger-v3.1-x86_64.apk) |

完整文件大小、SHA-256、构建命令和安装注意事项见：[v3.1.0 APK 文件说明](https://github.com/fzgfeng4-cyber/smart-ledger-project/blob/v3.1.0/release/v3.1.0/README.md)。

## 安装建议

1. 先在应用内导出或确认已有本地备份。
2. 下载对应 ABI 的 Release APK。
3. 使用 Android 文件管理器打开 APK 并完成安装。
4. 已安装旧版时，优先使用相同签名进行覆盖安装，不要同时保留多个 ABI 变体。

APK 仅用于个人本地安装，本项目没有发布到应用商店。不同 Android 设备的安装权限和兼容性提示以设备实际表现为准。

## 数据与隐私

- 账目使用本地 SQLite 保存。
- 金额以整数分保存，避免浮点误差。
- 删除账目使用软删除，统计默认排除已删除记录。
- OCR、分类建议和批量解析在本地完成；用户仍需在确认页面核对识别结果。
- Web 原型目录 `frontend/` 和 `backend/` 作为独立历史验证项目保留，不是 Android App 的运行依赖。

## 项目目录

| 目录 | 用途 |
| --- | --- |
| `mobile/` | Flutter Android App、Dart 领域逻辑、SQLite、测试和构建配置 |
| `docs/` | 产品、数据模型、分类规则、构建和发布说明 |
| `release/v3.1.0/` | 当前个人使用版 APK 和对应中文文件说明 |
| `frontend/` | Web 原型前端，独立保留 |
| `backend/` | Web 原型后端，独立保留 |

## 本地开发

进入 `mobile/` 后可使用以下命令进行基本验证：

```powershell
flutter test --no-pub
flutter analyze --no-pub
flutter build apk --release --split-per-abi --no-pub
```

提交代码前请保留数据库迁移、分类 code、软删除、金额整数分和本地日期规则，并避免把签名文件、用户数据库和构建缓存提交到仓库。

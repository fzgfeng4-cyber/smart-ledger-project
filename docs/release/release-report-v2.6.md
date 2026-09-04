# Smart Ledger Android APP V2.6 发布报告

## 一、最终结论

V2.6 已完成用户要求的功能收尾、Release 构建和手机安装验证，可以作为本阶段冻结版本。用户已于 **2026 年 9 月 3 日** 将 APK 安装到 Android 手机，反馈“使用还可以”。

V2.6 现冻结在 `v2-development` 分支，后续开发转入 V3，不再在 V2.6 上继续追加功能。

## 二、版本与基线

| 项目 | 实际值 |
| --- | --- |
| 项目 | Smart Ledger Android APP |
| 版本 | V2.6.0 |
| 分支 | `v2-development` |
| V1 基线 | `v1.0.0-frozen` |
| applicationId | `com.fzgfeng4.smartledger` |
| versionName | `2.6.0` |
| versionCode | `2` |
| 最低 Android 版本 | API 24 |
| target SDK | API 36 |
| 冻结日期 | 2026-09-03 |

## 三、V2.6 功能范围

- 批量记账与批量确认
- 首页组合搜索
- 分类统计
- 月度预算
- 微信 CSV 导入
- 支付宝 CSV 导入
- OCR 小票识别
- 本地 AI 分类输入
- SQLite 数据库 migration、备份恢复和软删除兼容
- 导入、批量、OCR、AI 结果先进入草稿或确认页，用户确认后才正式入库
- 首页布局调整：顶部沿用 V1 标题和统计，中间显示最近账目，底部显示预算、搜索账目和快速记账
- 修复 Release 构建产物缺少 Material Icons 字体导致的小图标全部消失问题

## 四、质量验证

| 检查项 | 结果 |
| --- | --- |
| 全量 Flutter 测试 | 通过，205 个测试 |
| `dart analyze --format machine` | 通过，无诊断 |
| `flutter pub get` | 通过 |
| `git diff --check` | 通过 |
| Release APK 构建 | 通过 |
| Material Icons 字体检查 | 通过 |
| 手机安装验证 | 通过，用户反馈使用正常 |

已修复的阻塞问题：

1. 导入保存失败时显示导入页面自己的“导入保存失败，账本未修改，请重试。”反馈，不再复用旧的记账操作反馈。
2. 统计页加载状态使用真实的不确定进度，并修复首次加载与刷新竞态。
3. 清理旧 Flutter 构建状态后重新构建，避免旧路径和旧产物污染当前 APK。
4. 确认 APK 内包含 `FontManifest.json` 与 `MaterialIcons-Regular.otf`，恢复 Material 小图标显示。

## 五、Release APK

| 项目 | 实际值 |
| --- | --- |
| 路径 | `mobile/build/app/outputs/flutter-apk/app-release.apk` |
| 大小 | 85,118,318 字节，约 81.2 MB |
| SHA-256 | `60ECBC36F4B34A04EAC1DFF57543C6D5CEC6EB0A25E3367607CA566D9ECEE47B` |
| `versionName` | `2.6.0` |
| `versionCode` | `2` |
| Material Icons | `FontManifest.json`、`fonts/MaterialIcons-Regular.otf` 均存在 |

APK 是本地构建产物，`mobile/build/` 已被 Git 忽略，不纳入源码提交。签名材料也不进入仓库：

- `mobile/android/release-keystore/smartledger-release.jks`
- `mobile/android/key.properties`

## 六、权限与隐私

当前 V2.6 Manifest：

- 声明 `android.permission.CAMERA`，仅供用户主动使用 OCR 拍照入口。
- 移除 `android.permission.INTERNET` 和 `android.permission.ACCESS_NETWORK_STATE`。
- 未声明短信、通讯录、录音、定位等权限。
- OCR 和 AI 分类保持本地处理，不把图片或文字上传云端。
- OCR 原图不会作为账目数据直接入库；识别结果先进入草稿确认流程。

## 七、用户安装验证范围

用户已完成 APK 安装并进行实际使用，反馈使用正常。本报告只记录已确认的安装和使用结果，不把一次用户冒烟使用夸大为所有设备、所有系统版本和所有流程均已逐项验收。

自动化测试仍是 V2.6 回归证据；目标设备、Android 系统版本、输入法和具体操作步骤未形成逐项设备测试记录的部分，继续作为已知限制保留。

## 八、已知限制

1. Release APK 体积约 81.2 MB，包含离线 OCR 能力及多 ABI 构建内容。
2. 当前版本只提供本地能力，不提供云同步、登录、多用户或云端 AI。
3. V2.6 冻结后不再追加功能；V3 需求、数据迁移和兼容策略另行设计。
4. GitHub 仓库保存源码、测试和发布文档，不保存 APK、构建缓存、签名文件和用户数据。

## 九、交付判断

| 判断项 | 结果 |
| --- | --- |
| 自动化测试通过 | 是 |
| Dart 静态分析通过 | 是 |
| 当前源码 Release APK 已构建 | 是 |
| APK 包含 Material Icons | 是 |
| 用户手机安装验证 | 是 |
| V1 冻结基线保持不变 | 是 |
| V2.6 可以冻结 | 是 |
| V3 是否开始 | 否，留待后续明确需求 |

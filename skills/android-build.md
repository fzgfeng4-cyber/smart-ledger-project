# Android Build Agent 工作规则

## 1. 开始前必须读取

Android Build Agent 开始任何工作前，必须先读取：

- `PROJECT.md`
- `docs/android-v1-plan.md`
- `docs/mobile-architecture.md`

可以参考其他 Android V1 文档，但本阶段不需要读取或修改 `frontend/`、`backend/`。它们仍然是 Web Prototype，只能作为历史业务参考，不能作为 Android APP V1 的运行依赖。

## 2. 当前职责

Android Build Agent 本阶段只负责创建一个健康、能构建的 Flutter Android 空项目骨架。

本阶段允许完成：

1. 检查本机 Flutter / Dart 环境。
2. 检查 Android SDK。
3. 检查 Java / JDK。
4. 检查 Gradle。
5. 检查 Android licenses。
6. 创建标准 Flutter `mobile/` 项目骨架。
7. 设置 APP 名称为 `Smart Ledger`。
8. 设置 Android `applicationId` / `namespace` 为 `com.fzgfeng4.smartledger`。
9. 核验 `minSdk` / `targetSdk` / `compileSdk`。
10. 检查 `AndroidManifest.xml` 和合并后的 Manifest 权限。
11. 添加已经冻结的基础 Flutter 依赖。
12. 验证空 Flutter APP 可以分析和构建 debug APK。

正式报告写入：

- `docs/android-build-report.md`

必要时只允许更新：

- `PROJECT.md` 中 Android Build 阶段状态和证据摘要。

## 3. 文件边界

允许创建和修改：

- `mobile/`
- `docs/android-build-report.md`
- `PROJECT.md` 中与 Android Build 阶段状态直接相关的内容

禁止修改：

- `frontend/`
- `backend/`

禁止为了让构建通过而改写 Web Prototype、删除旧文件、重构旧前后端，或把 Flutter APP 设计成依赖 FastAPI、Python、localhost、浏览器或外部 Backend。

## 4. 固定项目参数

Android Build Agent 必须遵守以下已冻结参数：

| 项目 | 值 |
| --- | --- |
| APP 显示名称 | `Smart Ledger` |
| Android `applicationId` | `com.fzgfeng4.smartledger` |
| Android `namespace` | `com.fzgfeng4.smartledger` |
| `minSdk` | 以 `docs/mobile-architecture.md` 冻结的 API 24 起步原则为准 |
| 运行架构 | Flutter + Dart + APP 内部业务逻辑 + 手机本地 SQLite |

`targetSdk` 和 `compileSdk` 必须根据当前本机 Flutter SDK、Android SDK 和 Android 构建要求实测确认，不得凭空使用过期版本号。

如果 `flutter create` 模板生成的包名、namespace 或 Android 配置与上述参数不一致，只能做最小必要调整，并在 `docs/android-build-report.md` 记录调整原因和文件路径。

## 5. 创建骨架规则

创建 `mobile/` 前必须确认：

- 当前目录确实是 Smart Ledger 项目根目录。
- `mobile/` 尚不存在，或其内容确认为本阶段可接管的 Flutter 骨架；如果已存在且来源不明，必须停止并报告。
- `frontend/`、`backend/` 不会被覆盖。

推荐以标准 Flutter 工具创建骨架，例如：

```text
flutter create --platforms=android --org com.fzgfeng4 --project-name smartledger mobile
```

创建后必须核对：

- `mobile/pubspec.yaml`
- `mobile/lib/main.dart`
- `mobile/android/app/build.gradle` 或 Flutter 当前模板对应的 Gradle 配置文件
- `mobile/android/app/src/main/AndroidManifest.xml`
- Android `namespace`
- Android `applicationId`
- APP label / 显示名称

本阶段可以保留 Flutter 模板默认首页，但不得把它扩展成正式记账页面。

## 6. 依赖规则

只允许添加当前 Android V1 架构已经确定、后续 V1 必须使用的基础依赖。

允许的基础依赖及用途：

| 依赖 | 当前用途 |
| --- | --- |
| `provider` | `Provider + ChangeNotifier` 状态管理。 |
| `sqflite` | 手机本地 SQLite 数据访问。 |
| `path` | 拼接数据库路径和文件路径。 |
| `path_provider` | 获取 APP 私有目录、数据库目录或临时导出目录。 |

暂不添加，除非后续阶段单独确认：

- `share_plus`
- Android SAF 相关插件
- `intl`
- `sqflite_common_ffi`

禁止添加：

- OCR 包。
- 网络请求包。
- AI / LLM SDK。
- 相机、相册或媒体包。
- 通知包。
- 权限管理包。
- 后台任务包。
- 云同步、Firebase、登录注册相关包。
- 支付平台 SDK。
- 复杂图表包。

每一个新增依赖都必须在 `docs/android-build-report.md` 说明用途。不得为了未来功能提前加入依赖。

## 7. Android 权限规则

Android APP V1 当前是本地离线一句话记账 APP，必须遵守最小权限原则。

当前不要申请：

- 相机。
- 相册或媒体读取。
- 通知。
- 短信。
- 通讯录。
- 无障碍。
- 后台服务。
- 外部存储。
- 读取其他 APP 数据。

如果当前 V1 不需要 `INTERNET`，不要为了未来功能提前添加。

SQLite 数据库应使用 APP 私有目录，不应为数据库申请外部存储权限。备份功能后续优先使用 Android 正常系统文件选择/保存机制，但本阶段不实现备份业务。

Android Build Agent 必须检查：

- 源 `AndroidManifest.xml`。
- Gradle 合并后的 Manifest，若当前环境能生成。
- debug APK 权限清单，若当前环境能构建。

如果模板或插件引入了不符合 V1 的权限，必须记录来源并优先通过最小配置修正；如果无法确认来源，停止并报告主 Agent。

## 8. 验证命令

后续正式执行时至少需要验证：

```text
flutter --version
flutter doctor
flutter pub get
flutter analyze
flutter build apk --debug
```

如果本机提供 Android SDK 工具，还应尽量核对：

```text
java -version
flutter doctor --android-licenses
```

执行验证时必须明确区分失败类型：

- Flutter 未安装。
- Dart 不可用。
- Android SDK 缺失。
- JDK 问题。
- Android licenses 问题。
- Gradle 问题。
- 网络下载问题。
- 当前沙箱或权限问题。
- 项目代码问题。

不能因为环境问题胡乱修改项目代码。网络下载或 SDK license 交互如果需要额外授权，应停止并向主 Agent 报告。

## 9. 本阶段禁止事项

Android Build Agent 本阶段不得实现：

- Transaction SQLite schema。
- Repository 正式实现。
- 一句话 Parser。
- 分类规则。
- 正式记账页面。
- CRUD。
- 统计。
- 删除撤销。
- 备份业务。
- V2/V3 功能。
- 最终 release APK 交付。

允许构建 debug APK 仅用于验证空 Flutter APP 骨架健康，不等同于 Android APP V1 完成或 APK Delivery。

## 10. 报告要求

`docs/android-build-report.md` 必须使用简体中文，并至少记录：

- 读取了哪些文档。
- 本机 Flutter / Dart / Android SDK / JDK / Gradle / licenses 检查结果。
- `mobile/` 是否由标准 Flutter 工具创建。
- APP 名称、`applicationId`、`namespace`、`minSdk`、`targetSdk`、`compileSdk` 的实测值。
- 新增依赖列表和每个依赖的当前用途。
- Manifest 权限检查结果。
- 执行过的验证命令和结果。
- 如果失败，明确失败属于环境、网络、权限、license、Gradle 还是项目代码问题。
- 本阶段没有实现业务代码、没有修改 Web Prototype、没有交付最终 APK。

报告必须区分：

- 已验证。
- 未验证。
- 被环境阻塞。
- 留给后续 Agent 的工作。

## 11. 完成后必须汇报

Android Build Agent 完成后必须向主 Agent 汇报：

- 是否成功创建 `mobile/` Flutter Android 骨架。
- 是否成功设置 APP 名称和包名。
- 是否成功添加基础依赖。
- `flutter analyze` 是否通过。
- `flutter build apk --debug` 是否通过。
- 当前 Android Manifest 权限是否符合 V1 最小权限原则。
- 是否创建或更新了 `docs/android-build-report.md`。
- 是否存在阻塞后续 Mobile Data / Classification / Flutter UI 的问题。

完成后停止，不进入 Mobile Data、Classification Migration、Flutter UI、SQLite Implementation、App Integration、Mobile Test、Mobile Review 或 APK Delivery 阶段。

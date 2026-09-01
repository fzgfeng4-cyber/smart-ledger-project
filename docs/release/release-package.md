# Smart Ledger Android APP V1 交付包

## 交付状态

- 产品版本：`1.0.0`
- Android `versionCode`：`1`
- applicationId：`com.fzgfeng4.smartledger`
- 应用名称：`Smart Ledger`
- 交付日期：2026-09-01
- Flutter 静态检查：通过
- Flutter 测试：`51/51` 通过
- Release APK 构建：已存在
- App Bundle 构建：已存在

## 交付文件

| 类型 | 实际路径 | 大小 |
| --- | --- | ---: |
| Release APK | `mobile/build/app/outputs/flutter-apk/app-release.apk` | 50,577,900 字节 |
| Release AAB | `mobile/build/app/outputs/bundle/release/app-release.aab` | 49,656,516 字节 |
| 用户测试清单 | `docs/release/uat-checklist.md` | 本目录 |
| 发布说明 | `docs/release/release-notes-v1.0.0.md` | 本目录 |
| 最终交付报告 | `docs/release/final-delivery-report.md` | 本目录 |

## 完整性校验

| 文件 | SHA-256 |
| --- | --- |
| `app-release.apk` | `927E4F035F4E83A947BE6102C573013FE049A1F8B4BE4E3ECD65A9F376EE12AA` |
| `app-release.aab` | `CEAAD1D77F9804CEDC33BB1EB65EFF95F46B84BC627B673A661295608A80D01B` |

## 交付范围

已包含 Smart Ledger V1 的本地记账能力：

- 一句话记账、Parser 和 Classification
- SQLite 本地持久化与 Repository
- 新增、编辑、软删除、撤销恢复
- 账单列表、分页和统计刷新
- JSON 备份与恢复
- Provider + ChangeNotifier 状态管理
- 中文优先的 Flutter Android UI

未包含 OCR、微信或支付宝导入、云同步、登录、多用户、通知监听及其他 V2/V3 功能。

## 交付前注意事项

- 当前 Release 构建配置使用 Android debug signing，仅适合内部验收和候选包分发；正式上架前必须替换为组织持有的 release keystore，并安全保管签名材料。
- 当前环境未连接 Android 真机，APK 安装、首次启动和硬件键盘行为需要在目标设备上执行 `uat-checklist.md`。
- Git 仓库在本轮开始时尚无提交，归档状态以最终 `Release Archive Report` 为准。

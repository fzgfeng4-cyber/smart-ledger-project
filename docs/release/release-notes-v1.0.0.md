# Smart Ledger Android APP V1 发布说明

## 版本信息

- 版本号：`1.0.0`
- Android `versionCode`：`1`
- applicationId：`com.fzgfeng4.smartledger`
- 发布日期：2026-09-01

## 主要功能

- 中文一句话记账入口
- Parser 解析与 Classification 分类确认
- 收入和支出新增、编辑、软删除及撤销恢复
- 账单列表、分页加载和首页统计
- SQLite 本地持久化
- JSON 备份和恢复
- 空状态、加载状态、错误状态和未保存草稿保护
- Material 3 风格 Flutter Android 界面

## 验证结果

- `flutter analyze`：通过，0 个问题
- `flutter test`：通过，51/51
- Release APK：已生成
- App Bundle：已生成
- 自动化备份恢复：通过，包含 100 条账目恢复与统计一致性验证

## 已知限制

- 当前 Release 构建已使用本地 release keystore 并完成签名校验；签名材料不进入 Git。正式应用商店发布前仍应按组织发布流程管理签名和密钥保管。
- 当前未连接 Android 真机，安装、首次启动和设备级输入法验收需要在目标设备上补做。
- 备份恢复仅支持当前 `backup_version = 1` 和 `database_version = 1`。
- 当前仅提供本地能力，不提供云同步、登录、多用户或第三方平台导入。

## 未来规划

V1 发布后再根据真实使用反馈评估后续版本。OCR、第三方平台导入、云同步、账号体系和高级报表不属于本版本交付范围。

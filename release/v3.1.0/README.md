# Smart Ledger v3.1.0 个人使用 APK

## 版本信息

- 应用版本：`3.1.0+3`
- Android `versionCode`：`2003`
- `applicationId`：`com.fzgfeng4.smartledger`
- 发布分支：`v2-development`
- 构建类型：Release，按 ABI 分包
- 本目录用途：个人手机本地安装

## APK 文件

| 文件 | 目标设备 | 大小（字节） | SHA-256 |
| --- | --- | ---: | --- |
| `SmartLedger-v3.1.apk` | `arm64-v8a`，推荐大多数安卓手机 | 32,043,857 | `CB61DC9EB8042927F10172FAEA852E9D4E9A6BC295F4D35043509E8D405F6043` |
| `SmartLedger-v3.1-armeabi-v7a.apk` | `armeabi-v7a`，较旧的 32 位 ARM 手机 | 25,270,891 | `CF5051D60E8F188E4EE7DBB2953FD81F7746DA70C3B9A2BD02BAB5FBE1766300` |
| `SmartLedger-v3.1-x86_64.apk` | `x86_64`，部分模拟器或 Intel Android 设备 | 34,161,912 | `7CDB0E9A67D38F6024532D6AFA98D2BD8F5C0C3236BA344EBA6CCCBAC32531A9` |

## 推荐安装

本人手机优先安装 `SmartLedger-v3.1.apk`。一台手机只需安装与自身 ABI 匹配的一个 APK，不要同时安装多个 ABI 版本。

如果手机已经安装旧版 Smart Ledger，建议先在应用内完成备份，再进行覆盖安装。相同签名的覆盖安装通常会保留本地账目数据；本阶段没有连接真机进行安装验证。

## 本版本内容

- 保留记账、编辑、删除、撤销、搜索、预算、OCR、导入、备份、分类和统计功能。
- 支持统计页月度和年度视图、收入与支出趋势、支出分类明细。
- 支持更紧凑的新增账目确认流程和批量自然语言记账。
- 保留中文 OCR 识别和本地 SQLite 数据存储。

## 构建与校验记录

- 构建命令：`flutter build apk --release --split-per-abi --no-pub`
- 上一阶段全量 Flutter 测试：`253/253` 通过。
- ASCII 临时路径静态分析：无 `error`，保留 3 个已知提示。
- 中文路径静态分析：Flutter 分析服务器触发 `FormatException: Unterminated string`，判定为路径环境问题。
- `git diff --check`：通过。
- 本阶段未上传应用商店，也未进行真机安装验收。

## 未上传的构建文件

`app-debug.apk`、通用 `app-release.apk`、`.sha1` 校验副本和 Flutter 构建缓存不属于本个人安装包目录，因此没有一并上传。

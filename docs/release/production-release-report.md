# Smart Ledger Android APP V1 生产发布报告

## 发布信息

| 项目 | 结果 |
| --- | --- |
| 项目名称 | Smart Ledger Android APP V1 |
| packageName | `com.fzgfeng4.smartledger` |
| versionName | `1.0.0` |
| versionCode | `1` |
| 签名别名 | `smartledger` |
| 签名类型 | JKS，RSA 2048，SHA256withRSA |
| 证书有效期 | 2026-09-01 至 2054-01-17 |

## 构建产物

| 产物 | 实际路径 | 大小 |
| --- | --- | ---: |
| Release APK | `G:\DevTools\AndroidEnv\workspace\smart-ledger-project\mobile\build\app\outputs\flutter-apk\app-release.apk` | 50,577,900 字节 |
| Release AAB | `G:\DevTools\AndroidEnv\workspace\smart-ledger-project\mobile\build\app\outputs\bundle\release\app-release.aab` | 49,656,589 字节 |

## SHA-256

| 文件 | SHA-256 |
| --- | --- |
| `app-release.apk` | `0DE4E69F424DEED9B1C1E4EAC54C4A1CBC4E58AC45E1529CA1DFCCD750D925A8` |
| `app-release.aab` | `6D37EDD529119EE909301D46673732BD7C272668ABE2C694967D837A910569D8` |

## 签名摘要

- APK `apksigner verify`：通过
- APK Signature Scheme v2：通过
- 签名者数量：1
- 证书 DN：`CN=Smart Ledger, OU=Mobile, O=Smart Ledger, L=US, ST=US, C=US`
- 证书 SHA-256：`3C:2D:C1:B2:ED:25:86:45:74:FD:B1:25:E7:82:7A:A1:F3:74:CD:A9:D7:88:A0:FD:70:01:DA:5A:01:22:DF:EB`
- 公钥算法：RSA，2048 bit
- AAB `jarsigner -verify`：通过
- 当前已不再使用 Android Debug Keystore

签名材料位于本地：

- `mobile/android/release-keystore/smartledger-release.jks`
- `mobile/android/key.properties`

两个文件已加入 `.gitignore`，没有进入 Git 归档。签名密码未写入本报告。

## 包元数据

`aapt dump badging` 验证结果：

- package：`com.fzgfeng4.smartledger`
- versionCode：`1`
- versionName：`1.0.0`
- application-label：`Smart Ledger`
- launchable activity：`com.fzgfeng4.smartledger.MainActivity`

## 权限清单

APK 的 `aapt dump permissions` 仅发现：

- `com.fzgfeng4.smartledger.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION`

这是 AndroidX 自动生成的签名级应用内权限，用于非导出组件约束。

以下权限均未发现：

- `android.permission.INTERNET`
- `android.permission.CAMERA`
- `android.permission.READ_SMS`
- `android.permission.SEND_SMS`
- `android.permission.READ_CONTACTS`
- `android.permission.RECORD_AUDIO`
- `android.permission.ACCESS_FINE_LOCATION`

补充：合并 Manifest 中的 `android.permission.DUMP` 仅作为 AndroidX ProfileInstaller receiver 的组件访问约束属性出现，并非应用声明的 `uses-permission`。

## 验证结果

- `flutter pub get`：PASS
- `flutter analyze`：PASS，0 个问题
- `flutter test`：PASS，51/51
- `flutter build apk --release`：PASS
- `flutter build appbundle`：PASS
- APK 签名验证：PASS
- AAB 签名验证：PASS
- 包名和版本验证：PASS
- 禁止权限检查：PASS

## 最终状态

- 正式签名构建：PASS
- 真机安装验证（UAT）：未执行，当前 `adb devices` 无设备
- Production Release Ready：NO

未执行真机 UAT，因此不能将本报告标记为完整生产发布就绪。连接目标 Android 设备后，应执行安装、首次启动、数据库初始化、快速记账、编辑、删除、恢复、分页、统计和中文输入验收。

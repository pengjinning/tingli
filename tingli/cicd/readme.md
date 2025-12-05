# tingli CI/CD 使用说明（Android）

本目录用于 Android 构建与上传，脚本会自动生成 version.json 并上传到服务器，供客户端更新检查。

## 脚本

- 编译并上传：`sh cicd/scripts/build-and-upload-android.sh`

## 产物与服务器路径

- 本地产物：
	- `build/app/outputs/flutter-apk/tingli-android.apk`
	- `build/app/outputs/flutter-apk/version.json`
- 服务器目录：`124.220.58.234:/var/www/html/tingli/download/`
- 对外地址：`https://www.weiyuai.cn/tingli/download/`

服务器存在同名文件时会自动备份到 `download/backup/`。

## version.json 结构

```json
{
	"platform": "android",
	"versionName": "1.0.0",
	"versionCode": 1,
	"downloadUrl": "https://www.weiyuai.cn/tingli/download/tingli-android.apk",
	"sizeBytes": 12345678,
	"sha256": "<apk_sha256>",
	"forceUpdate": false,
	"releasedAt": "2025-01-01T00:00:00Z",
	"changelog": ""
}
```

## 前置条件

- Flutter 构建环境可用
- 已配置 Android 签名（release）并启用 V1/V2
- 本机可 SSH/SCP 至服务器并具备写权限

## 常见问题

- 构建失败：确保执行过 `flutter pub get`，并检查 Android SDK/JDK
- 上传失败：检查 SSH 连接与服务器权限
- 客户端未提示更新：确认 version.json 的 `versionCode` 大于当前安装包的 `buildNumber`，且下载 URL 正确

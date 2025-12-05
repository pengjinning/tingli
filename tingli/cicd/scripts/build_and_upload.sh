#!/bin/bash
# 睡前听力 APK 打包和上传脚本（仅 SSH 私钥方式）

set -euo pipefail

echo "🚀 开始构建 APK..."

# 进入 tingli 目录（脚本位于 apps/tingli/cicd，因此上一级即为 apps/tingli）
cd "$(dirname "$0")/.." || exit 1

## 1) 编译前：自动升级版本号（仅递增 + 后的构建号）
echo "🔢 升级版本号（递增 build number）..."
if grep -q '^version:' pubspec.yaml; then
  awk 'BEGIN{updated=0} 
    /^version: / && updated==0 { 
      # $2 形如 1.0.0+1
      split($2, ver, /\+/); 
      verName = ver[1]; 
      code = ver[2] + 0; 
      code = code + 1; 
      printf("version: %s+%d\n", verName, code); 
      updated=1; next 
    } 
    { print $0 }' pubspec.yaml > pubspec.yaml.tmp && mv pubspec.yaml.tmp pubspec.yaml
else
  echo "❌ 未在 pubspec.yaml 中找到 version 字段，无法升级版本号" && exit 1
fi

# 清理并获取依赖
echo "📦 清理并获取依赖..."
flutter clean
flutter pub get

# 构建 APK
echo "🔨 构建 Release APK..."
flutter build apk --release

APK_PATH="build/app/outputs/flutter-apk/app-release.apk"
TARGET_NAME="tingli.apk"

if [ ! -f "$APK_PATH" ]; then
  echo "❌ APK 文件不存在: $APK_PATH"
  exit 1
fi

# 获取版本信息
VERSION=$(grep '^version:' pubspec.yaml | awk '{print $2}')
VERSION_NAME=$(echo "$VERSION" | cut -d'+' -f1)
VERSION_CODE=$(echo "$VERSION" | cut -d'+' -f2)

echo "📱 版本: $VERSION_NAME (Build $VERSION_CODE)"

# 为确保与实际 APK 一致，优先从 APK 中读取 versionName/versionCode（若可用 aapt）
APK_VNAME=""
APK_VCODE=""

# 查找 aapt 可执行文件
find_aapt() {
  if command -v aapt >/dev/null 2>&1; then
    command -v aapt
    return
  fi
  for base in "${ANDROID_SDK_ROOT:-}" "${ANDROID_HOME:-}"; do
    if [ -n "$base" ] && [ -d "$base/build-tools" ]; then
      # 选择最高版本号的 build-tools 目录
      AAPT_CANDIDATE=$(ls -1d "$base/build-tools"/* 2>/dev/null | sort -V | tail -n1)/aapt
      if [ -x "$AAPT_CANDIDATE" ]; then
        echo "$AAPT_CANDIDATE"
        return
      fi
    fi
  done
}

AAPT_BIN=$(find_aapt || true)
if [ -n "${AAPT_BIN:-}" ] && [ -x "$AAPT_BIN" ]; then
  BADGING=$("$AAPT_BIN" dump badging "$APK_PATH" 2>/dev/null || true)
  if [ -n "$BADGING" ]; then
    APK_VCODE=$(echo "$BADGING" | sed -n "s/.*versionCode='\([0-9][0-9]*\)'.*/\1/p" | head -n1)
    APK_VNAME=$(echo "$BADGING" | sed -n "s/.*versionName='\([^']*\)'.*/\1/p" | head -n1)
  fi
fi

if [ -n "$APK_VNAME" ] && [ -n "$APK_VCODE" ]; then
  if [ "$APK_VNAME" != "$VERSION_NAME" ] || [ "$APK_VCODE" != "$VERSION_CODE" ]; then
    echo "ℹ️  检测到 APK 实际版本为: $APK_VNAME (Build $APK_VCODE)，与 pubspec 中 $VERSION_NAME (Build $VERSION_CODE) 不一致，version.json 将以 APK 为准。"
  fi
  VERSION_NAME="$APK_VNAME"
  VERSION_CODE="$APK_VCODE"
else
  echo "⚠️  未能从 APK 读取版本，version.json 将使用 pubspec.yaml 中的版本。"
fi

# 输出到 assets/waiyanshe
echo "📝 生成 version.json 到 assets/waiyanshe..."
mkdir -p assets/waiyanshe
BASE_URL=${BASE_URL:-https://www.weiyuai.cn/weiyuai/english}
cat > assets/waiyanshe/version.json <<EOF
{
  "version": "$VERSION_NAME",
  "versionCode": $VERSION_CODE,
  "androidUrl": "$BASE_URL/$TARGET_NAME",
  "updatedAt": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "changelog": [
    "优化播放器界面，支持音乐播放器风格",
    "添加播放速度控制（0.5x-2.0x）",
    "支持顺序播放和记忆播放位置",
    "添加每日打卡和睡前定时功能",
    "支持字幕点击跳转"
  ]
}
EOF

# 将 APK 复制到 assets/waiyanshe 目录
echo "📁 复制 APK 到 assets/waiyanshe..."
cp -f "$APK_PATH" "assets/waiyanshe/$TARGET_NAME"

echo "📤 准备上传到服务器..."

# 服务器配置（可通过环境变量覆盖）
SERVER_HOST=${SERVER_HOST:-124.220.58.234}
SERVER_USER=${SERVER_USER:-root}
SERVER_DIR=${SERVER_DIR:-/var/www/html/weiyuai/english}

echo "目标服务器: $SERVER_HOST"
echo "目标路径: $SERVER_DIR"

KEY_FILE="${SSH_KEY_PATH:-$HOME/.ssh/id_rsa}"
if [ ! -f "$KEY_FILE" ]; then
  echo "❌ 未找到 SSH 私钥: $KEY_FILE"
  echo "👉 请先按 cicd/ssh_rsa.md 配置免密登录，或通过环境变量 SSH_KEY_PATH 指定密钥路径。"
  exit 1
fi

echo "📂 确保远端目录存在: $SERVER_DIR"
ssh -i "$KEY_FILE" -o StrictHostKeyChecking=accept-new "${SERVER_USER}@${SERVER_HOST}" "mkdir -p '$SERVER_DIR'"

echo "🔐 使用 SSH 私钥上传: $KEY_FILE"
scp -i "$KEY_FILE" -o StrictHostKeyChecking=accept-new "assets/waiyanshe/$TARGET_NAME" "${SERVER_USER}@${SERVER_HOST}:${SERVER_DIR}/$TARGET_NAME"
scp -i "$KEY_FILE" -o StrictHostKeyChecking=accept-new assets/waiyanshe/version.json "${SERVER_USER}@${SERVER_HOST}:${SERVER_DIR}/version.json"

DOWNLOAD_PAGE="assets/waiyanshe/download.html"
echo "📤 上传下载页面..."
if [ -f "$DOWNLOAD_PAGE" ]; then
  scp -i "$KEY_FILE" -o StrictHostKeyChecking=accept-new "$DOWNLOAD_PAGE" "${SERVER_USER}@${SERVER_HOST}:${SERVER_DIR}/download.html"
  echo "✅ 下载页面上传成功"
else
  echo "⚠️  下载页面不存在，跳过上传"
fi

echo "✅ 上传完成！"
echo "下载地址: $BASE_URL/$TARGET_NAME"
echo "版本信息: $BASE_URL/version.json"
echo "下载页面: $BASE_URL/download.html"

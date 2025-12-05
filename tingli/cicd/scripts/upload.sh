#!/bin/bash
# 仅上传：先复制 APK 到 assets/waiyanshe，再在该目录生成 version.json，最后上传
# 用法：
#   bash ./cicd/upload.sh
# 可用环境变量：
#   SERVER_HOST, SERVER_USER, SERVER_DIR, SSH_KEY_PATH, BASE_URL

set -euo pipefail

# 进入 tingli 目录（脚本位于 apps/tingli/cicd，因此上一级即为 apps/tingli）
cd "$(dirname "$0")/.." || exit 1

APK_BUILD="build/app/outputs/flutter-apk/app-release.apk"
TARGET_NAME="tingli.apk"
APK_LOCAL="assets/waiyanshe/$TARGET_NAME"
JSON_LOCAL="assets/waiyanshe/version.json"

if [ ! -f "$APK_BUILD" ]; then
  echo "❌ 构建产物不存在：$APK_BUILD，请先执行打包（或运行 build_and_upload.sh）"
  exit 1
fi

echo "📁 准备 assets/waiyanshe 目录..."
mkdir -p assets/waiyanshe

echo "📦 复制 APK 到 $APK_LOCAL..."
cp -f "$APK_BUILD" "$APK_LOCAL"

# 读取版本：优先从 APK 提取，失败时回退 pubspec.yaml
echo "🔎 读取版本信息..."
VERSION=$(grep '^version:' pubspec.yaml | awk '{print $2}') || true
VERSION_NAME=${VERSION%%+*}
VERSION_CODE=${VERSION##*+}

find_aapt() {
  if command -v aapt >/dev/null 2>&1; then
    command -v aapt
    return
  fi
  for base in "${ANDROID_SDK_ROOT:-}" "${ANDROID_HOME:-}"; do
    if [ -n "$base" ] && [ -d "$base/build-tools" ]; then
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
  BADGING=$("$AAPT_BIN" dump badging "$APK_BUILD" 2>/dev/null || true)
  if [ -n "$BADGING" ]; then
    APK_VCODE=$(echo "$BADGING" | sed -n "s/.*versionCode='\([0-9][0-9]*\)'.*/\1/p" | head -n1)
    APK_VNAME=$(echo "$BADGING" | sed -n "s/.*versionName='\([^']*\)'.*/\1/p" | head -n1)
    if [ -n "$APK_VNAME" ] && [ -n "$APK_VCODE" ]; then
      VERSION_NAME="$APK_VNAME"
      VERSION_CODE="$APK_VCODE"
    fi
  fi
fi

echo "📝 生成 version.json 到 assets/waiyanshe..."
BASE_URL=${BASE_URL:-https://www.weiyuai.cn/weiyuai/english}
cat > "$JSON_LOCAL" <<EOF
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

# 服务器配置
SERVER_HOST=${SERVER_HOST:-124.220.58.234}
SERVER_USER=${SERVER_USER:-root}
SERVER_DIR=${SERVER_DIR:-/var/www/html/weiyuai/english}
KEY_FILE="${SSH_KEY_PATH:-$HOME/.ssh/id_rsa}"

if [ ! -f "$KEY_FILE" ]; then
  echo "❌ 未找到 SSH 私钥: $KEY_FILE"
  echo "👉 请先按 cicd/ssh_rsa.md 配置免密登录，或通过环境变量 SSH_KEY_PATH 指定密钥路径。"
  exit 1
fi

echo "📂 确保远端目录存在: $SERVER_DIR"
ssh -i "$KEY_FILE" -o StrictHostKeyChecking=accept-new "${SERVER_USER}@${SERVER_HOST}" "mkdir -p '$SERVER_DIR'"

echo "📤 上传 APK 与 version.json..."
scp -i "$KEY_FILE" -o StrictHostKeyChecking=accept-new "$APK_LOCAL" "${SERVER_USER}@${SERVER_HOST}:${SERVER_DIR}/$TARGET_NAME"
scp -i "$KEY_FILE" -o StrictHostKeyChecking=accept-new "$JSON_LOCAL" "${SERVER_USER}@${SERVER_HOST}:${SERVER_DIR}/version.json"

DOWNLOAD_PAGE="assets/waiyanshe/download.html"
if [ -f "$DOWNLOAD_PAGE" ]; then
  scp -i "$KEY_FILE" -o StrictHostKeyChecking=accept-new "$DOWNLOAD_PAGE" "${SERVER_USER}@${SERVER_HOST}:${SERVER_DIR}/download.html"
fi

echo "✅ 上传完成"

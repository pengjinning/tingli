#!/usr/bin/env bash
###
# Build and upload Android APK for tingli, then generate and upload version.json
###
set -euo pipefail

DIST=build/app/outputs/flutter-apk
SERVER_HOST=124.220.58.234
BASE_DOMAIN="https://www.weiyuai.cn"
BASE_DOWNLOAD_URL="$BASE_DOMAIN/download"
TARGET_DIST=/var/www/html/weiyuai/download/
BACKUP_DIST=/var/www/html/weiyuai/download/backup/
APP_NAME="tingli"
APK_BASENAME="${APP_NAME}-android_$(date +"%Y%m%d_%H%M%S").apk" # 本地产物
APK_FIXED_NAME="${APP_NAME}-android.apk"                               # 远端固定名
DATE_SUFFIX=$(date +"%Y%m%d_%H%M%S")

ensure_remote_dirs() {
  ssh root@"$SERVER_HOST" "mkdir -p '$BACKUP_DIST' '$TARGET_DIST'"
}

backup_and_upload() {
  local local_file="$1"
  local remote_filename="$2"
  if ssh root@"$SERVER_HOST" "[ -f '$TARGET_DIST$remote_filename' ]"; then
    ssh root@"$SERVER_HOST" "cp '$TARGET_DIST$remote_filename' '$BACKUP_DIST${remote_filename}_$DATE_SUFFIX'" || true
  fi
  scp -r "$local_file" root@"$SERVER_HOST":"$TARGET_DIST$remote_filename"
}

# Generate version.json
generate_version_json() {
  local apk_path="./$DIST/$APK_BASENAME"
  local pubspec_path="./pubspec.yaml"
  local json_output_path="./$DIST/version.json"

  local version_line version_name version_code size_bytes sha256 released_at download_url
  version_line=$(grep -E "^version:\s*" "$pubspec_path" | head -n1 | sed -E 's/^version:\s*//')
  version_name=$(echo "$version_line" | cut -d'+' -f1 | xargs)
  version_code=$(echo "$version_line" | cut -d'+' -f2 | xargs)

  size_bytes=$(stat -f%z "$apk_path" 2>/dev/null || stat -c%s "$apk_path" 2>/dev/null)
  if command -v shasum >/dev/null 2>&1; then
    sha256=$(shasum -a 256 "$apk_path" | awk '{print $1}')
  elif command -v sha256sum >/dev/null 2>&1; then
    sha256=$(sha256sum "$apk_path" | awk '{print $1}')
  else
    sha256=""
  fi
  released_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  download_url="$BASE_DOWNLOAD_URL/$APK_FIXED_NAME"

  cat > "$json_output_path" <<EOF
{
  "platform": "android",
  "versionName": "$version_name",
  "versionCode": $version_code,
  "downloadUrl": "$download_url",
  "sizeBytes": $size_bytes,
  "sha256": "$sha256",
  "forceUpdate": false,
  "releasedAt": "$released_at",
  "changelog": ""
}
EOF
}

main() {
  ensure_remote_dirs
  flutter build apk
  mv "./$DIST/app-release.apk" "./$DIST/$APK_BASENAME"

  generate_version_json

  if command -v apksigner >/dev/null 2>&1; then
    apksigner verify --print-certs "./$DIST/$APK_BASENAME" || true
  fi
  if command -v aapt >/dev/null 2>&1; then
    aapt dump badging "./$DIST/$APK_BASENAME" | head -n 20 || true
  fi

  backup_and_upload "./$DIST/$APK_BASENAME" "$APK_FIXED_NAME"
  backup_and_upload "./$DIST/version.json" "${APP_NAME}-android-version.json"
  echo "TingLi Android build uploaded successfully."
}

main "$@"

#!/bin/bash

# 后台播放功能验证脚本
# 用于快速验证后台播放配置是否正确

set -e

echo "🎵 随睡听 后台播放功能验证"
echo "================================"
echo ""

# 检查当前目录
if [ ! -f "pubspec.yaml" ]; then
    echo "❌ 错误: 请在项目根目录运行此脚本"
    exit 1
fi

echo "📋 检查配置文件..."
echo ""

# 检查 iOS Info.plist
echo "1️⃣ 检查 iOS Info.plist..."
if grep -q "UIBackgroundModes" ios/Runner/Info.plist; then
    if grep -q "<string>audio</string>" ios/Runner/Info.plist; then
        echo "   ✅ iOS 后台音频模式已配置"
    else
        echo "   ⚠️  iOS Info.plist 存在 UIBackgroundModes 但缺少 audio 模式"
    fi
else
    echo "   ❌ iOS Info.plist 缺少 UIBackgroundModes 配置"
fi

# 检查 iOS AppDelegate
echo ""
echo "2️⃣ 检查 iOS AppDelegate..."
if grep -q "import AVFoundation" ios/Runner/AppDelegate.swift; then
    echo "   ✅ iOS AppDelegate 已导入 AVFoundation"
else
    echo "   ❌ iOS AppDelegate 缺少 AVFoundation 导入"
fi

if grep -q "AVAudioSession" ios/Runner/AppDelegate.swift; then
    echo "   ✅ iOS AppDelegate 已配置音频会话"
else
    echo "   ❌ iOS AppDelegate 缺少音频会话配置"
fi

# 检查 Android 权限
echo ""
echo "3️⃣ 检查 Android 权限..."
if grep -q "FOREGROUND_SERVICE" android/app/src/main/AndroidManifest.xml; then
    echo "   ✅ Android FOREGROUND_SERVICE 权限已添加"
else
    echo "   ⚠️  Android 缺少 FOREGROUND_SERVICE 权限"
fi

if grep -q "WAKE_LOCK" android/app/src/main/AndroidManifest.xml; then
    echo "   ✅ Android WAKE_LOCK 权限已添加"
else
    echo "   ⚠️  Android 缺少 WAKE_LOCK 权限"
fi

# 检查 BetterPlayer 配置
echo ""
echo "4️⃣ 检查 BetterPlayer 配置..."
if grep -q "handleLifecycle" lib/pages/player_page.dart; then
    echo "   ✅ PlayerPage 已配置 handleLifecycle"
else
    echo "   ℹ️  PlayerPage 未显式设置 handleLifecycle (使用默认值 true)"
fi

echo ""
echo "================================"
echo "📝 验证总结"
echo ""
echo "配置检查完成！"
echo ""
echo "下一步操作："
echo "1. 连接 iOS 或 Android 设备"
echo "2. 运行: flutter clean && flutter pub get"
echo "3. 运行: flutter run --release"
echo "4. 按照 docs/BACKGROUND_PLAYBACK_VERIFICATION.md 进行测试"
echo ""
echo "详细文档:"
echo "- docs/BACKGROUND_PLAYBACK.md - 配置说明"
echo "- docs/BACKGROUND_PLAYBACK_VERIFICATION.md - 测试指南"
echo ""

#!/bin/zsh
set -euo pipefail
# Build a distributable GlobalTrans.dmg (app only; models stay outside the image).
#
#   zsh Scripts/make-dmg.sh
#
# Output: dist/GlobalTrans-<version>.dmg
# Install: open the dmg, drag GlobalTrans.app to Applications.
# Models: copy OvisOCR2-4bit and Hy-MT2-1.8B-4bit next to the app,
# into a Models folder beside it, or into ~/Applications.
#
# Gatekeeper: this script ad-hoc / locally signs. For public download you still
# need a Developer ID certificate and `xcrun notarytool submit`.

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT/App/Info.plist")"
DIST="$ROOT/dist"
STAGE="$DIST/dmg-root"
DMG="$DIST/GlobalTrans-$VERSION.dmg"
VOL="GlobalTrans $VERSION"

rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"

GT_APP_PATH="$STAGE/GlobalTrans.app" GT_INSTALL_HOME=0 zsh "$ROOT/Scripts/bundle-app.sh" --release

ln -s /Applications "$STAGE/Applications"

cat > "$STAGE/Read Me.txt" <<EOF
GlobalTrans $VERSION

1. 把 GlobalTrans.app 拖进 Applications。
2. 自行下载模型（本镜像不含权重），放到下面任一位置：
     • 和应用同一目录
     • 同一目录下的 Models 文件夹
     • 或 ~/Applications
   文件夹名：
     OvisOCR2-4bit
     Hy-MT2-1.8B-4bit
3. 从菜单栏打开。第一次截图时允许屏幕录制。
4. 需要改路径或用远程 API：面板里的 Models…

推荐权重：
  https://huggingface.co/mlx-community/OvisOCR2-4bit
  https://huggingface.co/mlx-community/Hy-MT2-1.8B-4bit

应用不会在 Documents / Application Support / Caches 里写工作文件。
截图只留在内存。模型由你自己管理。
EOF

hdiutil create \
  -volname "$VOL" \
  -srcfolder "$STAGE" \
  -ov \
  -format UDZO \
  "$DMG"

echo "dmg: $DMG"
echo "size: $(du -h "$DMG" | awk '{print $1}')"
echo "this image does not include OCR/translation models"
echo "for App Store / public web: sign with Developer ID and notarize"

#!/bin/zsh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

METALLIB_SRC=""
if [[ -f .xcodebuild/Build/Products/Debug/mlx-swift_Cmlx.bundle/Contents/Resources/default.metallib ]]; then
  METALLIB_SRC=".xcodebuild/Build/Products/Debug/mlx-swift_Cmlx.bundle/Contents/Resources/default.metallib"
elif [[ -f .xcodebuild/Build/Products/Release/mlx-swift_Cmlx.bundle/Contents/Resources/default.metallib ]]; then
  METALLIB_SRC=".xcodebuild/Build/Products/Release/mlx-swift_Cmlx.bundle/Contents/Resources/default.metallib"
fi

if [[ -z "$METALLIB_SRC" ]]; then
  echo "Metal shaders are missing. Building mlx-swift_Cmlx with xcodebuild…"
  xcodebuild -scheme gt-ocr-cli \
    -configuration Debug \
    -destination 'platform=macOS,arch=arm64' \
    -derivedDataPath .xcodebuild \
    -skipPackagePluginValidation \
    -skipMacroValidation \
    build || true
  METALLIB_SRC=".xcodebuild/Build/Products/Debug/mlx-swift_Cmlx.bundle/Contents/Resources/default.metallib"
fi

if [[ ! -f "$METALLIB_SRC" ]]; then
  echo "error: could not find default.metallib (mlx-swift Metal shaders)"
  exit 1
fi

SIGN_IDENTITY="-"
if IDENTITY="$("$ROOT/Scripts/ensure-signing-identity.sh" 2>/dev/null)" && [[ -n "$IDENTITY" ]]; then
  SIGN_IDENTITY="$IDENTITY"
fi

swift build -c release --product GlobalTrans
BIN="$ROOT/.build/release/GlobalTrans"
APP="$ROOT/.build/GlobalTrans.app"
STABLE="$HOME/Applications/GlobalTrans.app"

rm -rf "$APP" "$STABLE"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$HOME/Applications"
cp "$BIN" "$APP/Contents/MacOS/GlobalTrans"
cp "$METALLIB_SRC" "$APP/Contents/MacOS/mlx.metallib"
cp "$ROOT/App/Info.plist" "$APP/Contents/Info.plist"
printf '%s\n' "$ROOT" > "$APP/Contents/Resources/workspace-root"
codesign --force --deep --sign "$SIGN_IDENTITY" "$APP"

ditto "$APP" "$STABLE"
codesign --force --deep --sign "$SIGN_IDENTITY" "$STABLE"

# .build copy would otherwise be a second TCC client. Point it at the installed app.
rm -rf "$APP"
ln -s "$STABLE" "$APP"

echo "signed with: $SIGN_IDENTITY"
echo "installed $STABLE"
echo ".build/GlobalTrans.app is a symlink to $STABLE"
echo "OCR model: GT_MODEL_PATH or $ROOT/OvisOCR2-4bit"
echo "translation model: GT_TRANSLATION_PATH or $ROOT/Hy-MT2-1.8B-4bit"
echo "run: open $STABLE"
echo "quit every other GlobalTrans copy first, then Allow Screen Recording once"

#!/bin/zsh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

RELEASE_BUNDLE=0
if [[ "${1:-}" == "--release" ]]; then
  RELEASE_BUNDLE=1
fi

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
APP="${GT_APP_PATH:-$ROOT/.build/GlobalTrans.app}"
STABLE="$HOME/Applications/GlobalTrans.app"
INSTALL_HOME="${GT_INSTALL_HOME:-1}"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/GlobalTrans"
cp "$METALLIB_SRC" "$APP/Contents/MacOS/mlx.metallib"
cp "$ROOT/App/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/App/Icons/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
cp "$ROOT/App/Icons/MenuBarIconTemplate.pdf" "$APP/Contents/Resources/MenuBarIconTemplate.pdf"
if [[ "$RELEASE_BUNDLE" -eq 0 ]]; then
  printf '%s\n' "$ROOT" > "$APP/Contents/Resources/workspace-root"
fi

# SwiftMath ships Latin Modern in a resource bundle; Preview formulas need it.
for bundle in \
  "$ROOT/.build/release/"*.bundle \
  "$ROOT/.build/arm64-apple-macosx/release/"*.bundle
do
  [[ -d "$bundle" ]] || continue
  name="$(basename "$bundle")"
  if [[ "$name" == SwiftMath* || "$name" == *SwiftMath* ]]; then
    cp -R "$bundle" "$APP/Contents/Resources/$name"
  fi
done
codesign --force --deep --sign "$SIGN_IDENTITY" "$APP"

if [[ "$INSTALL_HOME" == "1" ]]; then
  mkdir -p "$HOME/Applications"
  rm -rf "$STABLE"
  ditto "$APP" "$STABLE"
  codesign --force --deep --sign "$SIGN_IDENTITY" "$STABLE"
  if [[ "$APP" == "$ROOT/.build/GlobalTrans.app" ]]; then
    rm -rf "$APP"
    ln -s "$STABLE" "$APP"
  fi
  echo "installed $STABLE"
  echo ".build/GlobalTrans.app is a symlink to $STABLE"
fi

echo "signed with: $SIGN_IDENTITY"
echo "app: $APP"
if [[ "$RELEASE_BUNDLE" -eq 1 ]]; then
  echo "release bundle: models next to the app, in Models/, or ~/Applications"
else
  echo "OCR model: GT_MODEL_PATH or $ROOT/OvisOCR2-4bit"
  echo "translation model: GT_TRANSLATION_PATH or $ROOT/Hy-MT2-1.8B-4bit"
fi
if [[ "$INSTALL_HOME" == "1" ]]; then
  echo "run: open $STABLE"
  echo "quit every other GlobalTrans copy first, then Allow Screen Recording once"
fi

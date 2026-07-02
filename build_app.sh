#!/bin/bash
# Builds WaterMark.app from the Swift package.
set -eo pipefail
cd "$(dirname "$0")"

echo "[1/4] Compiling (release)..."
swift build -c release

APP="WaterMark.app"
BIN=".build/release/WaterMark"

echo "[2/4] Assembling $APP..."
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/WaterMark"
cp Info.plist "$APP/Contents/Info.plist"

if [ -f AppIcon.png ]; then
  echo "      Generating app icon..."
  ICONSET="$(mktemp -d)/AppIcon.iconset"
  mkdir -p "$ICONSET"
  for size in 16 32 128 256 512; do
    sips -z "$size" "$size"           AppIcon.png --out "$ICONSET/icon_${size}x${size}.png"    >/dev/null
    sips -z "$((size*2))" "$((size*2))" AppIcon.png --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
  done
  iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
fi

echo "[3/4] Ad-hoc code signing..."
codesign --force --sign - "$APP"

echo "[4/4] Done: $(pwd)/$APP"
echo "  Run it:   open $APP"
echo "  Install:  mv $APP /Applications/   (recommended for Launch-at-login)"

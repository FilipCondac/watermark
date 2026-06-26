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
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/WaterMark"
cp Info.plist "$APP/Contents/Info.plist"

echo "[3/4] Ad-hoc code signing..."
codesign --force --sign - "$APP"

echo "[4/4] Done: $(pwd)/$APP"
echo "  Run it:   open $APP"
echo "  Install:  mv $APP /Applications/   (recommended for Launch-at-login)"

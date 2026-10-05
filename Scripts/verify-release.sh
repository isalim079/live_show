#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

APP_BUNDLE="$ROOT_DIR/build/Release/LiveWallpaper.app"
DMG_PATH="$ROOT_DIR/build/LiveWallpaper-v1.0.0.dmg"

echo "========================================="
echo " Verifying LiveWallpaper Release"
echo "========================================="

echo "[1/4] Checking .app bundle structure..."
test -f "$APP_BUNDLE/Contents/MacOS/LiveWallpaper"
test -f "$APP_BUNDLE/Contents/Info.plist"
test -f "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
test -f "$APP_BUNDLE/Contents/Resources/SampleAmbient.mp4"
echo "-> Bundle structure OK."

echo "[2/4] Verifying .app code signature..."
codesign -dvv "$APP_BUNDLE"
codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"
echo "-> Code signature OK."

echo "[3/4] Verifying DMG integrity..."
test -f "$DMG_PATH"
hdiutil verify "$DMG_PATH"
echo "-> DMG integrity OK."

echo "[4/4] Verifying DMG signature..."
codesign --verify --verbose=2 "$DMG_PATH"
echo "-> DMG code signature OK."

echo "========================================="
echo " All release verification checks PASSED!"
echo "========================================="

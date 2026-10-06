#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$ROOT_DIR"

APP_NAME="Live Show"
VERSION="1.1.0"
BUILD_DIR="$ROOT_DIR/build"
RELEASE_DIR="$BUILD_DIR/Release"
APP_BUNDLE="$RELEASE_DIR/$APP_NAME.app"
DMG_NAME="liveShow_v1.1.0.dmg"
FINAL_DMG="$BUILD_DIR/$DMG_NAME"
ROOT_DMG="$ROOT_DIR/$DMG_NAME"
DMG_STAGING="$BUILD_DIR/dmg_staging"
TMP_DMG="$BUILD_DIR/tmp_uncompressed.dmg"

echo "========================================="
echo " Packaging $DMG_NAME"
echo "========================================="

# 1. Ensure fresh release build
"$SCRIPT_DIR/build.sh"

# 2. Prepare DMG staging folder
echo "[1/4] Preparing DMG staging environment..."
rm -rf "$DMG_STAGING" "$TMP_DMG" "$FINAL_DMG" "$ROOT_DMG"
mkdir -p "$DMG_STAGING"

echo "Copying $APP_NAME.app to staging..."
cp -R "$APP_BUNDLE" "$DMG_STAGING/"

echo "Creating Applications symlink..."
ln -s /Applications "$DMG_STAGING/Applications"

# Include documentation / quick start
cat << 'EOF' > "$DMG_STAGING/READ_ME.txt"
Live Show for macOS
===================

To install:
1. Drag "Live Show" into the "Applications" folder.
2. Launch Live Show from Applications or Spotlight.
   If macOS blocks it: right-click the app → Open → Open.
3. Access controls from the menu bar icon.
4. Add your own MP4 / MOV videos or use the built-in ambient wallpaper.
5. For animated Lock Screen: open Settings in the app and use
   "Repair Lock Screen Integration" if needed.

Enjoy your live animated desktop!
EOF

# 3. Create compressed DMG using hdiutil
echo "[2/4] Generating disk image with hdiutil..."
hdiutil create \
    -volname "liveShow" \
    -srcfolder "$DMG_STAGING" \
    -ov \
    -format UDZO \
    -imagekey zlib-level=9 \
    "$FINAL_DMG"

# 4. Code Sign the DMG
echo "[3/4] Signing DMG..."
SIGN_IDENTITY="${CODE_SIGN_IDENTITY:-${DEVELOPER_ID_APPLICATION:-}}"
if [[ -z "$SIGN_IDENTITY" ]]; then
    KEYCHAIN_CERT=$(security find-identity -p codesigning -v 2>/dev/null | grep -E "Developer ID Application:" | head -n 1 | awk -F'"' '{print $2}' || true)
    if [[ -n "$KEYCHAIN_CERT" ]]; then
        SIGN_IDENTITY="$KEYCHAIN_CERT"
    else
        SIGN_IDENTITY="-"
    fi
fi

codesign --force --sign "$SIGN_IDENTITY" --timestamp=none "$FINAL_DMG"

# Also place a copy at workspace root for convenient immediate access
cp "$FINAL_DMG" "$ROOT_DMG"

# 5. Verify DMG
echo "[4/4] Verifying disk image..."
hdiutil verify "$FINAL_DMG"
codesign --verify --verbose=2 "$FINAL_DMG"

rm -rf "$DMG_STAGING" "$TMP_DMG"

echo "========================================="
echo " Release DMG successfully created!"
echo " Location: $FINAL_DMG"
echo " Convenient copy: $ROOT_DMG"
echo " Size: $(du -sh "$FINAL_DMG" | awk '{print $1}')"
echo "========================================="

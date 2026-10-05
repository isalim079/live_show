#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$ROOT_DIR"

APP_NAME="LiveWallpaper"
BUILD_DIR="$ROOT_DIR/build"
RELEASE_DIR="$BUILD_DIR/Release"
APP_BUNDLE="$RELEASE_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

echo "========================================="
echo " Building LiveWallpaper (Release Mode)"
echo "========================================="

# 1. Compile Release Binary with Swift Package Manager
echo "[1/5] Compiling Swift release binary..."
swift build -c release

BIN_PATH="$ROOT_DIR/.build/release/$APP_NAME"
if [[ ! -f "$BIN_PATH" ]]; then
    echo "Error: Binary not found at $BIN_PATH" >&2
    exit 1
fi

# 2. Assemble .app Bundle
echo "[2/5] Assembling $APP_NAME.app bundle..."
rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

cp "$BIN_PATH" "$MACOS_DIR/$APP_NAME"
chmod +x "$MACOS_DIR/$APP_NAME"

cp "$ROOT_DIR/Resources/Info.plist" "$CONTENTS_DIR/Info.plist"
echo -n "APPL????" > "$CONTENTS_DIR/PkgInfo"

if [[ -f "$ROOT_DIR/Resources/AppIcon.icns" ]]; then
    cp "$ROOT_DIR/Resources/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"
fi

if [[ -f "$ROOT_DIR/Resources/SampleAmbient.mp4" ]]; then
    cp "$ROOT_DIR/Resources/SampleAmbient.mp4" "$RESOURCES_DIR/SampleAmbient.mp4"
fi

# 3. Detect Signing Identity
echo "[3/5] Determining code signing identity..."
SIGN_IDENTITY="${CODE_SIGN_IDENTITY:-${DEVELOPER_ID_APPLICATION:-}}"

if [[ -z "$SIGN_IDENTITY" ]]; then
    # Try to find a Developer ID certificate in Keychain
    KEYCHAIN_CERT=$(security find-identity -p codesigning -v 2>/dev/null | grep -E "Developer ID Application:" | head -n 1 | awk -F'"' '{print $2}' || true)
    if [[ -n "$KEYCHAIN_CERT" ]]; then
        SIGN_IDENTITY="$KEYCHAIN_CERT"
        echo "Found Keychain Developer ID: $SIGN_IDENTITY"
    else
        # Try Apple Development
        DEV_CERT=$(security find-identity -p codesigning -v 2>/dev/null | grep -E "Apple Development:" | head -n 1 | awk -F'"' '{print $2}' || true)
        if [[ -n "$DEV_CERT" ]]; then
            SIGN_IDENTITY="$DEV_CERT"
            echo "Found Keychain Development Identity: $DEV_CERT"
        else
            SIGN_IDENTITY="-"
            echo "No Developer ID certificate found. Using production ad-hoc code signature (-s -) with Hardened Runtime."
        fi
    fi
fi

# 4. Code Sign App Bundle with Hardened Runtime & Entitlements
echo "[4/5] Code signing with identity: $SIGN_IDENTITY..."
ENTITLEMENTS="$ROOT_DIR/Resources/LiveWallpaper.entitlements"

codesign --force --deep \
    --options runtime \
    --sign "$SIGN_IDENTITY" \
    --entitlements "$ENTITLEMENTS" \
    --timestamp=none \
    "$APP_BUNDLE"

# 5. Verify Code Signature
echo "[5/5] Verifying bundle code signature..."
codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"

echo "========================================="
echo " Build successful: $APP_BUNDLE"
echo "========================================="

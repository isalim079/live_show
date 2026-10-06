#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$ROOT_DIR"

APP_NAME="Live Show"
SWIFT_TARGET="LiveWallpaper"
BUILD_DIR="$ROOT_DIR/build"
RELEASE_DIR="$BUILD_DIR/Release"
APP_BUNDLE="$RELEASE_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

echo "========================================="
echo " Building $APP_NAME (Release Mode)"
echo "========================================="

# 1. Compile Release Binary with Swift Package Manager
echo "[1/5] Compiling Swift release binary..."
swift build -c release

BIN_PATH="$ROOT_DIR/.build/release/$SWIFT_TARGET"
if [[ ! -f "$BIN_PATH" ]]; then
    echo "Error: Binary not found at $BIN_PATH" >&2
    exit 1
fi

# 2. Assemble .app Bundle
echo "[2/5] Assembling $APP_NAME.app bundle..."
rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

cp "$BIN_PATH" "$MACOS_DIR/$SWIFT_TARGET"
chmod +x "$MACOS_DIR/$SWIFT_TARGET"

cp "$ROOT_DIR/Resources/Info.plist" "$CONTENTS_DIR/Info.plist"
echo -n "APPL????" > "$CONTENTS_DIR/PkgInfo"

if [[ -f "$ROOT_DIR/Resources/AppIcon.icns" ]]; then
    cp "$ROOT_DIR/Resources/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"
fi

if [[ -f "$ROOT_DIR/Resources/SampleAmbient.mp4" ]]; then
    cp "$ROOT_DIR/Resources/SampleAmbient.mp4" "$RESOURCES_DIR/SampleAmbient.mp4"
fi

# 2b. Build LiveWallpaper.saver Screen Saver Bundle
echo "Building LiveWallpaper.saver screen saver bundle..."
SAVER_BUNDLE="$BUILD_DIR/LiveWallpaper.saver"
SAVER_BINARY_NAME="LiveWallpaperSaver"
rm -rf "$SAVER_BUNDLE"
mkdir -p "$SAVER_BUNDLE/Contents/MacOS"
mkdir -p "$SAVER_BUNDLE/Contents/Resources"

# CRITICAL: -install_name must use @rpath so dyld resolves correctly after install.
# Without this, the dylib embeds the build-time path (on this machine/drive),
# which breaks loading on lock screen when paths differ.
swiftc -emit-library \
    -Xlinker -install_name \
    -Xlinker "@rpath/$SAVER_BINARY_NAME" \
    -Xlinker -rpath -Xlinker "@loader_path" \
    "$ROOT_DIR/ScreenSaver/LiveWallpaperSaverView.swift" \
    -o "$SAVER_BUNDLE/Contents/MacOS/$SAVER_BINARY_NAME" \
    -framework ScreenSaver -framework AppKit -framework AVFoundation

cp "$ROOT_DIR/ScreenSaver/Info.plist" "$SAVER_BUNDLE/Contents/Info.plist"

# Bundle the sample video inside .saver so there's always a fallback at lock screen
if [[ -f "$ROOT_DIR/Resources/SampleAmbient.mp4" ]]; then
    cp "$ROOT_DIR/Resources/SampleAmbient.mp4" "$SAVER_BUNDLE/Contents/Resources/SampleAmbient.mp4"
fi

# Sign with deep flag so the bundle's Contents/MacOS binary is individually signed
SAVER_SIGN="${CODE_SIGN_IDENTITY:-}"
if [[ -z "$SAVER_SIGN" ]]; then
    SAVER_SIGN=$(security find-identity -p codesigning -v 2>/dev/null | grep -E "Developer ID Application:|Apple Development:" | head -n 1 | awk -F'"' '{print $2}' || true)
    [[ -z "$SAVER_SIGN" ]] && SAVER_SIGN="-"
fi
codesign --force --deep --sign "$SAVER_SIGN" --timestamp=none "$SAVER_BUNDLE"

cp -R "$SAVER_BUNDLE" "$RESOURCES_DIR/LiveWallpaper.saver"

# Install into ~/Library/Screen Savers
SAVER_INSTALL_DIR="$HOME/Library/Screen Savers"
mkdir -p "$SAVER_INSTALL_DIR"
rm -rf "$SAVER_INSTALL_DIR/LiveWallpaper.saver"
cp -R "$SAVER_BUNDLE" "$SAVER_INSTALL_DIR/LiveWallpaper.saver"

# CRITICAL: Strip quarantine and provenance extended attributes.
# macOS adds com.apple.quarantine and com.apple.provenance when files are
# copied from external drives or downloaded. These cause Gatekeeper to REJECT
# the .saver when ScreenSaverEngine tries to load it on the lock screen.
xattr -rc "$SAVER_INSTALL_DIR/LiveWallpaper.saver"

# Register as the active screen saver via defaults
defaults -currentHost write com.apple.screensaver moduleDict -dict \
  path "$SAVER_INSTALL_DIR/LiveWallpaper.saver" \
  moduleName "LiveWallpaper" \
  type 0
killall cfprefsd 2>/dev/null || true

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

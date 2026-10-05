#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

DMG_PATH="${1:-$ROOT_DIR/build/LiveWallpaper-v1.0.0.dmg}"

echo "========================================="
echo " LiveWallpaper Apple Notarization"
echo "========================================="

if [[ ! -f "$DMG_PATH" ]]; then
    echo "Error: DMG file not found at $DMG_PATH" >&2
    exit 1
fi

KEYCHAIN_PROFILE="${NOTARIZATION_PROFILE:-}"

if [[ -n "$KEYCHAIN_PROFILE" ]]; then
    echo "Submitting $DMG_PATH using notarytool keychain profile: $KEYCHAIN_PROFILE..."
    xcrun notarytool submit "$DMG_PATH" --keychain-profile "$KEYCHAIN_PROFILE" --wait

    echo "Stapling notarization ticket..."
    xcrun stapler staple "$DMG_PATH"
    echo "Notarization and stapling complete!"
else
    echo "Notice: NOTARIZATION_PROFILE not set."
    echo "To notarize with an Apple Developer account:"
    echo "1. Store credentials: xcrun notarytool store-credentials 'AC_PASSWORD' --apple-id 'user@example.com' --team-id 'TEAM_ID' --password 'app-specific-pwd'"
    echo "2. Run: NOTARIZATION_PROFILE='AC_PASSWORD' ./Scripts/notarize.sh"
fi

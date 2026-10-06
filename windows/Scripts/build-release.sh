#!/bin/bash
# Cross-publish Live Show for Windows (win-x64) using the .NET SDK.
# Works on macOS/Linux with EnableWindowsTargeting, and on Windows.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WINDOWS_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PROJECT="$WINDOWS_ROOT/LiveWallpaper/LiveWallpaper.csproj"
OUT_DIR="$WINDOWS_ROOT/Release_Build"
REPO_ROOT="$(cd "$WINDOWS_ROOT/.." && pwd)"
ZIP_NAME="liveShow_windows_v1.3.0.zip"

export PATH="${DOTNET_ROOT:-$HOME/.dotnet}:/usr/local/share/dotnet:$PATH"

if ! command -v dotnet >/dev/null 2>&1; then
  echo "dotnet SDK not found. Install .NET 8: https://dotnet.microsoft.com/download" >&2
  exit 1
fi

echo "========================================="
echo " Building Live Show (Windows portable)"
echo "========================================="

rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR"

dotnet publish "$PROJECT" \
  -c Release \
  -r win-x64 \
  --self-contained true \
  -p:PublishSingleFile=true \
  -p:IncludeNativeLibrariesForSelfExtract=true \
  -p:EnableCompressionInSingleFile=true \
  -o "$OUT_DIR"

rm -f "$OUT_DIR"/*.pdb

# Shareable zip at repo root
SHARE_DIR="$REPO_ROOT/build/windows_share"
rm -rf "$SHARE_DIR"
mkdir -p "$SHARE_DIR/LiveShow"
cp -R "$OUT_DIR"/. "$SHARE_DIR/LiveShow/"
cp "$WINDOWS_ROOT/README.md" "$SHARE_DIR/LiveShow/READ_ME.txt" 2>/dev/null || true

cat > "$SHARE_DIR/LiveShow/READ_ME.txt" << 'EOF'
Live Show for Windows (portable)
================================

1. Unzip this folder anywhere.
2. Double-click LiveWallpaper.exe
   If SmartScreen blocks it: More info → Run anyway.
3. Use the tray icon (near the clock):
   - Choose video…
   - Pause / Play
   - Start with Windows (optional)
   - Quit

Settings are saved in %AppData%\LiveShow\settings.json
EOF

rm -f "$REPO_ROOT/$ZIP_NAME" "$REPO_ROOT/build/$ZIP_NAME"
(
  cd "$SHARE_DIR"
  zip -ry "$REPO_ROOT/$ZIP_NAME" LiveShow
)
cp "$REPO_ROOT/$ZIP_NAME" "$REPO_ROOT/build/$ZIP_NAME"

echo "========================================="
echo " Portable build: $OUT_DIR"
echo " Share zip:      $REPO_ROOT/$ZIP_NAME"
echo " Optional: compile Scripts/LiveShow.iss with Inno Setup on Windows"
echo "========================================="
ls -lh "$OUT_DIR/LiveWallpaper.exe" "$REPO_ROOT/$ZIP_NAME"

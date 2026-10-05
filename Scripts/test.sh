#!/bin/bash
set -euo pipefail

echo "========================================="
echo " Running LiveWallpaper Test Suite"
echo "========================================="

swift test --verbose

echo "All tests passed successfully!"

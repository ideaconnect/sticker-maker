#!/usr/bin/env bash
# Play Store screenshot capture — mechanism (a): flutter drive + takeScreenshot.
#
#   bash tools/store_shots/run_driver.sh
#
# Env:
#   DEVICE           adb serial (default: a93d4403)
#   STORE_SHOTS_DIR  where the PNGs land (default: build/store-shots/raw)
#
# On Android `takeScreenshot` needs `convertFlutterSurfaceToImage()`, a one-way
# switch that on some engine versions disturbs rendering afterwards. If the
# frames come back blank, black, or visibly degraded, use the logcat runner
# instead: bash tools/store_shots/run_logcat.sh
set -euo pipefail

cd "$(dirname "$0")/../.."
REPO="$(pwd)"

DEVICE="${DEVICE:-a93d4403}"
STORE_SHOTS_DIR="${STORE_SHOTS_DIR:-$REPO/build/store-shots/raw}"
PKG="tech.idct.stickermaker"
REMOTE="/sdcard/Android/data/$PKG/files/store_fixture.jpg"

mkdir -p "$STORE_SHOTS_DIR"

echo "== device =="
adb -s "$DEVICE" get-state

echo "== pushing photo fixture =="
# MSYS_NO_PATHCONV stops Git Bash from rewriting the remote /sdcard path into a
# Windows Git-install path.
MSYS_NO_PATHCONV=1 adb -s "$DEVICE" push assets/branding/pies.jpg "$REMOTE"
MSYS_NO_PATHCONV=1 adb -s "$DEVICE" shell chmod 0666 "$REMOTE"
MSYS_NO_PATHCONV=1 adb -s "$DEVICE" shell ls -l "$REMOTE"

echo "== capturing to $STORE_SHOTS_DIR =="
STORE_SHOTS_DIR="$STORE_SHOTS_DIR" flutter drive \
  --driver test_driver/integration_test.dart \
  --target integration_test/store_screenshots_test.dart \
  -d "$DEVICE" \
  --dart-define=SHOT_MODE=driver

echo "== captured =="
ls -l "$STORE_SHOTS_DIR"

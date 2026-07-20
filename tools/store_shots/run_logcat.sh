#!/usr/bin/env bash
# Play Store screenshot capture — mechanism (b): logcat markers + screencap.
#
#   bash tools/store_shots/run_logcat.sh
#
# Env:
#   DEVICE           adb serial (default: a93d4403)
#   STORE_SHOTS_DIR  where the PNGs land (default: build/store-shots/raw)
#
# The integration test prints `STORE_SHOT_POSE:<name>` and then holds the pose
# perfectly still for ~2.6 s. This script tails logcat, and on each marker fires
# `adb exec-out screencap -p` into `<name>.png`. Nothing here touches
# `adb shell input` — the test drives the UI from inside the app process, which
# is the only thing that works on this phone.
#
# Captures the true composited screen at the device's native resolution
# (1440x3200 on the Redmi), so the frames still have to be composed onto a
# 1080x1920 canvas before upload.
set -euo pipefail

cd "$(dirname "$0")/../.."
REPO="$(pwd)"

DEVICE="${DEVICE:-a93d4403}"
STORE_SHOTS_DIR="${STORE_SHOTS_DIR:-$REPO/build/store-shots/raw}"
PKG="tech.idct.stickermaker"
REMOTE="/sdcard/Android/data/$PKG/files/store_fixture.jpg"

# Delay from seeing the marker to firing screencap: far enough into the hold
# window that the frame is settled, early enough to finish before it ends.
SETTLE_MS="${SETTLE_MS:-900}"

mkdir -p "$STORE_SHOTS_DIR"

echo "== device =="
adb -s "$DEVICE" get-state

echo "== pushing photo fixture =="
MSYS_NO_PATHCONV=1 adb -s "$DEVICE" push assets/branding/pies.jpg "$REMOTE"
MSYS_NO_PATHCONV=1 adb -s "$DEVICE" shell chmod 0666 "$REMOTE"
MSYS_NO_PATHCONV=1 adb -s "$DEVICE" shell ls -l "$REMOTE"

adb -s "$DEVICE" logcat -c || true

# --- marker watcher -------------------------------------------------------
watch_markers() {
  adb -s "$DEVICE" logcat -v brief flutter:I '*:S' | while IFS= read -r line; do
    case "$line" in
      *STORE_SHOT_POSE:*)
        name="${line##*STORE_SHOT_POSE:}"
        name="$(printf '%s' "$name" | tr -d '\r' | tr -d ' ')"
        [ -z "$name" ] && continue
        sleep "$(awk "BEGIN{print $SETTLE_MS/1000}")"
        out="$STORE_SHOTS_DIR/$name.png"
        # exec-out is binary-safe (no LF translation), unlike `adb shell`.
        adb -s "$DEVICE" exec-out screencap -p > "$out"
        echo "STORE_SHOT_WROTE:$out ($(wc -c < "$out") bytes)"
        ;;
      *STORE_SHOT_MANIFEST:*)
        echo "$line"
        break
        ;;
    esac
  done
}

watch_markers &
WATCHER=$!
trap 'kill "$WATCHER" 2>/dev/null || true; pkill -f "logcat -v brief flutter" 2>/dev/null || true' EXIT

echo "== capturing to $STORE_SHOTS_DIR =="
flutter test integration_test/store_screenshots_test.dart \
  -d "$DEVICE" \
  --dart-define=SHOT_MODE=logcat

# Give the watcher a beat to drain the last marker.
sleep 4

echo "== captured =="
ls -l "$STORE_SHOTS_DIR"

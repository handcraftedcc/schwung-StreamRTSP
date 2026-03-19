#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
IMAGE_NAME="move-anything-streamrtsp-builder"
OUTPUT_BASENAME="${OUTPUT_BASENAME:-streamrtsp-module}"

if [ -z "${CROSS_PREFIX:-}" ] && [ ! -f "/.dockerenv" ]; then
  echo "=== StreamRTSP Module Build (via Docker) ==="
  docker build -t "$IMAGE_NAME" -f "$SCRIPT_DIR/Dockerfile" "$REPO_ROOT"
  docker run --rm \
    -v "$REPO_ROOT:/build" \
    -u "$(id -u):$(id -g)" \
    -w /build \
    -e OUTPUT_BASENAME="$OUTPUT_BASENAME" \
    "$IMAGE_NAME" \
    ./scripts/build.sh
  exit 0
fi

CROSS_PREFIX="${CROSS_PREFIX:-aarch64-linux-gnu-}"

cd "$REPO_ROOT"
rm -rf build/module dist/streamrtsp
mkdir -p build/module dist/streamrtsp dist/streamrtsp/bin

# --- Bundle FFmpeg runtime dependency (dist/streamrtsp/bin/ffmpeg) ---
echo "Bundling ffmpeg..."
./scripts/build_ffmpeg.sh

# --- Stage RTSP backend helper (dist/streamrtsp/bin/streamrtsp_backend.sh) ---
echo "Staging RTSP backend..."
./scripts/build_rtsp_backend.sh

# --- Build DSP plugin ---
echo "Compiling v2 DSP plugin..."
"${CROSS_PREFIX}gcc" -O3 -g -shared -fPIC \
  src/dsp/streamrtsp_plugin.c \
  -o build/module/dsp.so \
  -Isrc/dsp \
  -lpthread -lm

cat src/module.json > dist/streamrtsp/module.json
[ -f src/help.json ] && cat src/help.json > dist/streamrtsp/help.json
cat src/ui.js > dist/streamrtsp/ui.js
cat src/ui_chain.js > dist/streamrtsp/ui_chain.js
cat build/module/dsp.so > dist/streamrtsp/dsp.so
chmod +x dist/streamrtsp/dsp.so

if [ -f src/runtime/streamrtsp_event.sh ]; then
  cat src/runtime/streamrtsp_event.sh > dist/streamrtsp/bin/streamrtsp_event.sh
  chmod +x dist/streamrtsp/bin/streamrtsp_event.sh
fi

# --- Package ---
PKG_TMP_DIR="$(mktemp -d)"
rm -f "dist/${OUTPUT_BASENAME}.tar.gz"
cp -a dist/streamrtsp "$PKG_TMP_DIR/streamrtsp"
(
  cd "$PKG_TMP_DIR"
  tar -czvf "$REPO_ROOT/dist/${OUTPUT_BASENAME}.tar.gz" streamrtsp/
)
rm -rf "$PKG_TMP_DIR"

echo "=== Build Complete ==="
echo "Module dir: dist/streamrtsp"
echo "Tarball: dist/${OUTPUT_BASENAME}.tar.gz"

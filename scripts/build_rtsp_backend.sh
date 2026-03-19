#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
SRC_BACKEND="$REPO_ROOT/src/runtime/streamrtsp_backend.sh"
SRC_DISCOVERY="$REPO_ROOT/src/runtime/screenstream_discovery.sh"
SRC_SCAN="$REPO_ROOT/src/runtime/screenstream_scan.sh"
DIST_BACKEND="$REPO_ROOT/dist/streamrtsp/bin/streamrtsp_backend.sh"
DIST_DISCOVERY="$REPO_ROOT/dist/streamrtsp/bin/screenstream_discovery.sh"
DIST_SCAN="$REPO_ROOT/dist/streamrtsp/bin/screenstream_scan.sh"

if [ ! -f "$SRC_BACKEND" ]; then
  echo "ERROR: Missing RTSP backend launcher source: $SRC_BACKEND" >&2
  exit 1
fi

mkdir -p "$REPO_ROOT/dist/streamrtsp/bin"
cat "$SRC_BACKEND" > "$DIST_BACKEND"
chmod +x "$DIST_BACKEND"

if [ -f "$SRC_DISCOVERY" ]; then
  cat "$SRC_DISCOVERY" > "$DIST_DISCOVERY"
  chmod +x "$DIST_DISCOVERY"
fi

if [ -f "$SRC_SCAN" ]; then
  cat "$SRC_SCAN" > "$DIST_SCAN"
  chmod +x "$DIST_SCAN"
fi

echo "RTSP backend staging complete:"
echo "  source: $SRC_BACKEND"
echo "  output: $DIST_BACKEND"

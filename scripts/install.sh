#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
MODULE_ID="streamrtsp"
DEVICE_HOST="${DEVICE_HOST:-move.local}"
RESTART_UI="${RESTART_UI:-0}"
REMOTE_BASE="/data/UserData/schwung/modules/sound_generators"
REMOTE_DIR="$REMOTE_BASE/$MODULE_ID"
DIST_DIR="$REPO_ROOT/dist/$MODULE_ID"

if [ ! -d "$DIST_DIR" ]; then
  echo "Error: $DIST_DIR not found. Run ./scripts/build.sh first."
  exit 1
fi

echo "=== Installing StreamRTSP Module ==="
echo "Device: $DEVICE_HOST"
echo "Remote: $REMOTE_DIR"
echo ""

ssh "root@$DEVICE_HOST" "mkdir -p $REMOTE_DIR"
scp -r "$DIST_DIR/"* "root@$DEVICE_HOST:$REMOTE_DIR/"
ssh "root@$DEVICE_HOST" "chown -R ableton:users $REMOTE_DIR"

case "$RESTART_UI" in
  1|true|TRUE|yes|YES|on|ON)
    echo "Restarting display-server to reload module UI..."
    ssh "root@$DEVICE_HOST" "pkill -f '/data/UserData/schwung/display-server' || true"
    ;;
esac

echo ""
echo "=== Install Complete ==="
echo "Module installed to $REMOTE_DIR"

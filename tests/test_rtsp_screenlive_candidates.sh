#!/usr/bin/env bash
set -euo pipefail

scan_script="src/runtime/screenstream_scan.sh"
discovery_script="src/runtime/screenstream_discovery.sh"

for f in "$scan_script" "$discovery_script"; do
  if [ ! -f "$f" ]; then
    echo "FAIL: Missing $f" >&2
    exit 1
  fi
done

if ! rg -q 'rtsp://%s:%s/screenlive' "$scan_script"; then
  echo "FAIL: subnet scan candidates should include /screenlive path" >&2
  exit 1
fi

if ! rg -q 'rtsp://\$\{host\}:8554/screenlive' "$discovery_script"; then
  echo "FAIL: ARP fallback candidates should include /screenlive path" >&2
  exit 1
fi

echo "PASS: screenlive candidate paths are wired"

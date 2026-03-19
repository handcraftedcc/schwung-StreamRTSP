#!/usr/bin/env bash
set -euo pipefail

discovery_script="src/runtime/screenstream_discovery.sh"

if [ ! -x "$discovery_script" ]; then
  echo "FAIL: Missing executable $discovery_script" >&2
  exit 1
fi

if ! rg -q 'DISCOVERY_WINDOW_SECONDS=' "$discovery_script"; then
  echo "FAIL: discovery should define a bounded discovery window" >&2
  exit 1
fi

if ! rg -q 'while \[ -z \"\$RESOLVED_URL\" \]' "$discovery_script"; then
  echo "FAIL: discovery should retry scans during the discovery window until resolved target is found" >&2
  exit 1
fi

if ! rg -q '/proc/net/arp' "$discovery_script"; then
  echo "FAIL: discovery should include ARP-based LAN fallback candidates" >&2
  exit 1
fi

if ! rg -q 'add_candidate \"Host \$\{host\} /screen\" \"rtsp://\$\{host\}:8554/screen\"' "$discovery_script"; then
  echo "FAIL: ARP fallback should include /screen candidate RTSP URLs for selection" >&2
  exit 1
fi

if ! rg -q 'add_candidate \"Host \$\{host\} /screenlive\" \"rtsp://\$\{host\}:8554/screenlive\"' "$discovery_script"; then
  echo "FAIL: ARP fallback should include /screenlive candidate RTSP URLs for selection" >&2
  exit 1
fi

echo "PASS: discovery window and candidate fallback are wired"

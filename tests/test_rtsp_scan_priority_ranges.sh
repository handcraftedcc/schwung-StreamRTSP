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

if ! rg -q 'discover_host_octet\(' "$scan_script"; then
  echo "FAIL: scan should detect local host octet to prioritize nearby addresses" >&2
  exit 1
fi

if ! rg -q 'for i in \$\(seq 200 254\)' "$scan_script"; then
  echo "FAIL: scan should prioritize high DHCP ranges (.200-.254) for Windows/mobile senders" >&2
  exit 1
fi

if rg -q 'RESOLVED_URL="\$last_endpoint"' "$discovery_script"; then
  echo "FAIL: last_sender should be a candidate, not forced auto-resolve target" >&2
  exit 1
fi

if ! rg -q '\[ -z "\$RESOLVED_URL" \] && \[ -x "\$SCAN_SCRIPT" \]' "$discovery_script"; then
  echo "FAIL: discovery should still run subnet scan when only candidate history exists" >&2
  exit 1
fi

echo "PASS: scan priority ranges and discovery fallback behavior are wired"

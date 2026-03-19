#!/usr/bin/env bash
set -euo pipefail

discovery_script="src/runtime/screenstream_discovery.sh"
scan_script="src/runtime/screenstream_scan.sh"

for f in "$discovery_script" "$scan_script"; do
  if [ ! -f "$f" ]; then
    echo "FAIL: Missing $f" >&2
    exit 1
  fi
done

if rg -q 'RESOLVED_URL="\$last_endpoint"' "$discovery_script"; then
  echo "FAIL: discovery should not force resolved_url from last sender" >&2
  exit 1
fi

if rg -q 'RESOLVED_URL="\$\{CANDIDATE_URLS\[0\]\}"' "$discovery_script"; then
  echo "FAIL: discovery should not auto-resolve first candidate before scan window" >&2
  exit 1
fi

if rg -q 'if \[ "\$count" -eq 0 \]; then' "$scan_script"; then
  echo "FAIL: scan should not skip supplemental range probe when ARP has candidates" >&2
  exit 1
fi

if ! rg -q 'Supplemental bounded range scan so non-ARP devices' "$scan_script"; then
  echo "FAIL: scan should include supplemental bounded range probe for non-ARP devices" >&2
  exit 1
fi

echo "PASS: discovery no-forced-resolve and supplemental scan are wired"

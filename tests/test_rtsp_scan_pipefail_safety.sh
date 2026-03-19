#!/usr/bin/env bash
set -euo pipefail

scan_script="src/runtime/screenstream_scan.sh"

if [ ! -f "$scan_script" ]; then
  echo "FAIL: Missing $scan_script" >&2
  exit 1
fi

if rg -q "awk '!seen\[\$0\]\+\+' \"\$host_file\" \| head -n" "$scan_script"; then
  echo "FAIL: scan host limiting must avoid awk|head under pipefail (can exit 141)" >&2
  exit 1
fi

if ! rg -Fq "awk -v max=\"\$MAX_HOSTS\" '!seen[\$0]++ {print; if (++n >= max) exit}' \"\$host_file\"" "$scan_script"; then
  echo "FAIL: scan host limiting should use single-process awk cap for pipefail safety" >&2
  exit 1
fi

echo "PASS: scan host limiting is pipefail-safe"

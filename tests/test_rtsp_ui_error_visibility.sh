#!/usr/bin/env bash
set -euo pipefail

ui_file="src/ui.js"

if [ ! -f "$ui_file" ]; then
  echo "FAIL: Missing $ui_file" >&2
  exit 1
fi

if ! rg -q "host_module_get_param\\('last_error'\\)" "$ui_file"; then
  echo "FAIL: UI should read last_error from module params" >&2
  exit 1
fi

if ! rg -q "status === 'error' && lastError" "$ui_file"; then
  echo "FAIL: UI should prefer detailed error text when status is error" >&2
  exit 1
fi

echo "PASS: UI shows detailed RTSP errors"

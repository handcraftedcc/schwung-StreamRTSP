#!/usr/bin/env bash
set -euo pipefail

ui_file="src/ui.js"

if [ ! -f "$ui_file" ]; then
  echo "FAIL: Missing $ui_file" >&2
  exit 1
fi

if ! rg -q 'function shouldShowDeviceList\(' "$ui_file"; then
  echo "FAIL: UI must define shouldShowDeviceList() for discovery fallback gating" >&2
  exit 1
fi

if ! rg -q "status === 'scanning'" "$ui_file"; then
  echo "FAIL: UI fallback gating must account for active scanning state" >&2
  exit 1
fi

if ! rg -q 'const showDeviceList = shouldShowDeviceList\(\);' "$ui_file"; then
  echo "FAIL: device list rendering should be gated by shouldShowDeviceList()" >&2
  exit 1
fi

if ! rg -q 'if \(showDeviceList\)' "$ui_file"; then
  echo "FAIL: device options should render only when discovery fallback is active" >&2
  exit 1
fi

echo "PASS: UI discovery fallback flow is wired"

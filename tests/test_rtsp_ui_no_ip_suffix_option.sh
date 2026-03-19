#!/usr/bin/env bash
set -euo pipefail

ui_file="src/ui.js"

if [ ! -f "$ui_file" ]; then
  echo "FAIL: Missing $ui_file" >&2
  exit 1
fi

if rg -q 'IP Suffix' "$ui_file"; then
  echo "FAIL: UI should not expose IP suffix controls" >&2
  exit 1
fi

if rg -q "host_module_set_param\('connect_suffix'" "$ui_file"; then
  echo "FAIL: UI should not trigger connect_suffix manual endpoint flow" >&2
  exit 1
fi

if rg -q 'Source IP Suffix' "$ui_file"; then
  echo "FAIL: UI should not open source suffix text entry" >&2
  exit 1
fi

echo "PASS: UI IP suffix controls removed"

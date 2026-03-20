#!/usr/bin/env bash
set -euo pipefail

ui_file="src/ui.js"

if [ ! -f "$ui_file" ]; then
  echo "FAIL: Missing $ui_file" >&2
  exit 1
fi

if ! rg -q 'IP Suffix:' "$ui_file"; then
  echo "FAIL: UI should expose IP suffix controls in manual mode" >&2
  exit 1
fi

if ! rg -q 'Port:' "$ui_file"; then
  echo "FAIL: UI should expose editable port in manual mode" >&2
  exit 1
fi

if ! rg -q 'Path:' "$ui_file"; then
  echo "FAIL: UI should expose editable path in manual mode" >&2
  exit 1
fi

if ! rg -q '\[Connect\]' "$ui_file"; then
  echo "FAIL: UI should expose Connect action in manual mode" >&2
  exit 1
fi

echo "PASS: UI manual endpoint controls are visible"

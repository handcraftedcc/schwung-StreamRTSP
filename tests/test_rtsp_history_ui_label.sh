#!/usr/bin/env bash
set -euo pipefail

ui_file="src/ui.js"

if [ ! -f "$ui_file" ]; then
  echo "FAIL: Missing $ui_file" >&2
  exit 1
fi

if ! rg -q 'function historyLabel\(' "$ui_file"; then
  echo "FAIL: UI should define historyLabel formatter" >&2
  exit 1
fi

if ! rg -q '\$\{suffix\}/\$\{path\}' "$ui_file"; then
  echo "FAIL: history list should display suffix/path only" >&2
  exit 1
fi

if ! rg -q 'Math\.min\(rawCount, MAX_HISTORY_ENTRIES\)' "$ui_file"; then
  echo "FAIL: UI should cap rendered history entries to module policy" >&2
  exit 1
fi

echo "PASS: history UI label and cap are wired"

#!/usr/bin/env bash
set -euo pipefail

ui_file="src/ui.js"

if [ ! -f "$ui_file" ]; then
  echo "FAIL: Missing $ui_file" >&2
  exit 1
fi

if ! rg -q '\[Past Connections\]' "$ui_file"; then
  echo "FAIL: UI should include a Past Connections action" >&2
  exit 1
fi

if ! rg -q 'showHistory' "$ui_file"; then
  echo "FAIL: UI should implement a dedicated history list mode" >&2
  exit 1
fi

if rg -q '\[Scan LAN\]' "$ui_file"; then
  echo "FAIL: manual mode UI should not expose Scan LAN action" >&2
  exit 1
fi

if rg -q "host_module_get_param\\('candidate_count'\\)" "$ui_file"; then
  echo "FAIL: manual mode UI should not render discovery candidate list" >&2
  exit 1
fi

echo "PASS: manual-mode UI flow is wired"

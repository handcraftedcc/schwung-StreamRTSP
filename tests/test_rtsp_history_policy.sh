#!/usr/bin/env bash
set -euo pipefail

plugin_file="src/dsp/streamrtsp_plugin.c"

if [ ! -f "$plugin_file" ]; then
  echo "FAIL: Missing $plugin_file" >&2
  exit 1
fi

if ! rg -q '^#define MAX_HISTORY_ENTRIES 5$' "$plugin_file"; then
  echo "FAIL: history should retain at most 5 endpoints" >&2
  exit 1
fi

if ! rg -q 'existing_idx == 0\) return;' "$plugin_file"; then
  echo "FAIL: duplicate most-recent endpoint should not rewrite history" >&2
  exit 1
fi

if ! rg -q 'snprintf\(entries\[0\], sizeof\(entries\[0\]\), "%s", endpoint\);' "$plugin_file"; then
  echo "FAIL: history should keep most recent endpoint at top" >&2
  exit 1
fi

echo "PASS: history retention and de-dup policy are wired"

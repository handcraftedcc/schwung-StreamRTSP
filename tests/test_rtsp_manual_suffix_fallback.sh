#!/usr/bin/env bash
set -euo pipefail

plugin_file="src/dsp/streamrtsp_plugin.c"
ui_file="src/ui.js"

for f in "$plugin_file" "$ui_file"; do
  if [ ! -f "$f" ]; then
    echo "FAIL: Missing $f" >&2
    exit 1
  fi
done

if ! rg -q 'strcmp\(key, "manual_suffix"\)' "$plugin_file"; then
  echo "FAIL: plugin must handle manual_suffix parameter" >&2
  exit 1
fi

if ! rg -q 'strcmp\(key, "connect_suffix"\)' "$plugin_file"; then
  echo "FAIL: plugin must handle connect_suffix action" >&2
  exit 1
fi

if ! rg -q 'strcmp\(key, "network_prefix"\)' "$plugin_file"; then
  echo "FAIL: plugin must expose network_prefix status" >&2
  exit 1
fi

if ! rg -q 'strcmp\(key, "manual_suffix"\)' "$plugin_file"; then
  echo "FAIL: plugin must expose manual_suffix status" >&2
  exit 1
fi

if rg -q 'IP Suffix' "$ui_file"; then
  echo "FAIL: UI should no longer expose IP suffix controls" >&2
  exit 1
fi

if rg -q "host_module_set_param\\('connect_suffix'" "$ui_file"; then
  echo "FAIL: UI should no longer trigger connect_suffix directly" >&2
  exit 1
fi

echo "PASS: manual suffix backend compatibility is preserved without UI controls"

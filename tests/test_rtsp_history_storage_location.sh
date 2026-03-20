#!/usr/bin/env bash
set -euo pipefail

plugin_file="src/dsp/streamrtsp_plugin.c"

if [ ! -f "$plugin_file" ]; then
  echo "FAIL: Missing $plugin_file" >&2
  exit 1
fi

if ! rg -q 'snprintf\(inst->history_path, sizeof\(inst->history_path\), "%s/history.env", inst->module_dir\);' "$plugin_file"; then
  echo "FAIL: history should be stored in module directory" >&2
  exit 1
fi

if ! rg -q 'snprintf\(legacy_path, sizeof\(legacy_path\), "%s/history.env", inst->cache_dir\);' "$plugin_file"; then
  echo "FAIL: history loader should support legacy cache migration" >&2
  exit 1
fi

echo "PASS: history storage location is module-local with legacy migration"

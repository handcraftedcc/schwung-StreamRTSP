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

if ! rg -q 'MANUAL_PATH_DEFAULT' "$plugin_file"; then
  echo "FAIL: plugin should define MANUAL_PATH_DEFAULT" >&2
  exit 1
fi

if ! rg -q 'manual_path\.env' "$plugin_file"; then
  echo "FAIL: plugin should persist manual path in cache" >&2
  exit 1
fi

if ! rg -q 'strcmp\(key, "manual_path"\)' "$plugin_file"; then
  echo "FAIL: plugin should support manual_path set/get params" >&2
  exit 1
fi

if ! rg -q 'rtsp://%s.%d:%d/%s' "$plugin_file"; then
  echo "FAIL: manual endpoint builder should include configurable path" >&2
  exit 1
fi

if ! rg -q 'openPathEditor' "$ui_file"; then
  echo "FAIL: UI should provide editable RTSP path field" >&2
  exit 1
fi

if ! rg -q "host_module_set_param\('manual_path'" "$ui_file"; then
  echo "FAIL: UI should persist manual path edits" >&2
  exit 1
fi

echo "PASS: manual path field is wired"

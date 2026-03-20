#!/usr/bin/env bash
set -euo pipefail

plugin_file="src/dsp/streamrtsp_plugin.c"
ui_file="src/ui.js"

if ! rg -q 'last_error_detail\[256\]' "$plugin_file"; then
  echo "FAIL: plugin should store persistent last_error_detail" >&2
  exit 1
fi

if ! rg -q 'if \(strcmp\(key, "last_error"\) == 0\)' "$plugin_file"; then
  echo "FAIL: plugin should expose last_error getter" >&2
  exit 1
fi

if ! rg -q '404 endpoint not found' "$plugin_file"; then
  echo "FAIL: plugin should classify 404 endpoint errors" >&2
  exit 1
fi

if ! rg -q '503 server unavailable' "$plugin_file"; then
  echo "FAIL: plugin should classify 503 server errors" >&2
  exit 1
fi

if ! rg -q "host_module_get_param\('last_error'\)" "$ui_file"; then
  echo "FAIL: UI should fetch last_error from plugin" >&2
  exit 1
fi

if ! rg -q 'Last error:' "$ui_file"; then
  echo "FAIL: UI should render Last error line" >&2
  exit 1
fi

echo "PASS: last error visibility checks passed"

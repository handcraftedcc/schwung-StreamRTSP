#!/usr/bin/env bash
set -euo pipefail

plugin_file="src/dsp/streamrtsp_plugin.c"

if [ ! -f "$plugin_file" ]; then
  echo "FAIL: Missing $plugin_file" >&2
  exit 1
fi

if ! rg -q 'last_log_offset' "$plugin_file"; then
  echo "FAIL: plugin should track per-attempt log offset for backend classification" >&2
  exit 1
fi

if ! rg -q 'read_runtime_log_since_offset' "$plugin_file"; then
  echo "FAIL: plugin should read runtime logs from per-attempt offset only" >&2
  exit 1
fi

if ! rg -q 'stat\(LOG_PATH' "$plugin_file"; then
  echo "FAIL: supervisor start should capture current log file size as offset baseline" >&2
  exit 1
fi

echo "PASS: log-window classification guard is wired"

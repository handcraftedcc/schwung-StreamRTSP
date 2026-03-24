#!/usr/bin/env bash
set -euo pipefail

plugin_file="src/dsp/streamrtsp_plugin.c"

if [ ! -f "$plugin_file" ]; then
  echo "FAIL: Missing $plugin_file" >&2
  exit 1
fi

if ! rg -q 'char log_path\[512\];' "$plugin_file"; then
  echo "FAIL: instance should track module-local log_path" >&2
  exit 1
fi

if ! rg -q 'snprintf\(inst->log_path, sizeof\(inst->log_path\), "%s/streamrtsp-runtime.log", inst->module_dir\);' "$plugin_file"; then
  echo "FAIL: create_instance should route runtime logs into module_dir" >&2
  exit 1
fi

if rg -q '/cache/streamrtsp-runtime\.log' "$plugin_file"; then
  echo "FAIL: runtime logs should not be hardcoded to cache path" >&2
  exit 1
fi

if ! rg -q 'open\(inst->log_path, O_WRONLY \| O_CREAT \| O_APPEND, 0644\)' "$plugin_file"; then
  echo "FAIL: child process stderr logging should use module-local log_path" >&2
  exit 1
fi

if ! rg -q 'execl\(backend_script,' "$plugin_file" || ! rg -q 'inst->log_path' "$plugin_file"; then
  echo "FAIL: backend should receive module-local log path argument" >&2
  exit 1
fi

echo "PASS: module-local runtime logging is wired"

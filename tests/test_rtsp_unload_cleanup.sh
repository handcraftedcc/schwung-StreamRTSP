#!/usr/bin/env bash
set -euo pipefail

plugin_file="src/dsp/streamrtsp_plugin.c"

if [ ! -f "$plugin_file" ]; then
  echo "FAIL: Missing $plugin_file" >&2
  exit 1
fi

if ! rg -q 'static void terminate_child' "$plugin_file"; then
  echo "FAIL: plugin should have a bounded child termination helper for unload safety" >&2
  exit 1
fi

if ! rg -q 'kill\(-pid, SIGTERM\)' "$plugin_file"; then
  echo "FAIL: child teardown should signal process group (SIGTERM) for full cleanup" >&2
  exit 1
fi

if ! rg -q 'kill\(-pid, SIGKILL\)' "$plugin_file"; then
  echo "FAIL: child teardown should escalate with process-group SIGKILL" >&2
  exit 1
fi

if ! rg -q 'setpgid\(0, 0\)' "$plugin_file"; then
  echo "FAIL: child workers should enter dedicated process groups" >&2
  exit 1
fi

if ! rg -q 'terminate_child\(&inst->scan_pid, &inst->scan_running\)' "$plugin_file"; then
  echo "FAIL: unload path should terminate discovery workers with bounded cleanup" >&2
  exit 1
fi

echo "PASS: unload cleanup safety scaffold is wired"

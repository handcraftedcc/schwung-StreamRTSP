#!/usr/bin/env bash
set -euo pipefail

plugin_file="src/dsp/streamrtsp_plugin.c"

if [ ! -f "$plugin_file" ]; then
  echo "FAIL: Missing $plugin_file" >&2
  exit 1
fi

if ! rg -q 'Always start with discovery so new senders can be found before connect' "$plugin_file"; then
  echo "FAIL: plugin startup should prioritize discovery before reconnecting last sender" >&2
  exit 1
fi

if rg -q 'if \(inst->auto_reconnect && inst->endpoint\[0\] != '\''\\0'\''\) \{\s*\(void\)supervisor_start\(inst, inst->endpoint, false\);' "$plugin_file"; then
  echo "FAIL: plugin should not auto-connect saved endpoint on instance create" >&2
  exit 1
fi

echo "PASS: startup discovery-first behavior is wired"

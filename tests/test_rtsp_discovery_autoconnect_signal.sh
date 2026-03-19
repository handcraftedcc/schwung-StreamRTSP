#!/usr/bin/env bash
set -euo pipefail

discovery_script="src/runtime/screenstream_discovery.sh"
plugin_file="src/dsp/streamrtsp_plugin.c"

for f in "$discovery_script" "$plugin_file"; do
  if [ ! -f "$f" ]; then
    echo "FAIL: Missing $f" >&2
    exit 1
  fi
done

if ! rg -q 'resolved_url' "$discovery_script"; then
  echo "FAIL: discovery script must write resolved_url for auto-connectable endpoint" >&2
  exit 1
fi

if ! rg -q 'resolved_name' "$discovery_script"; then
  echo "FAIL: discovery script should write resolved_name for resolved_url context" >&2
  exit 1
fi

if ! rg -q 'strcmp\(line, "resolved_url"\)' "$plugin_file"; then
  echo "FAIL: plugin discovery parser must read resolved_url" >&2
  exit 1
fi

if ! rg -q 'strcmp\(line, "resolved_name"\)' "$plugin_file"; then
  echo "FAIL: plugin discovery parser must read resolved_name" >&2
  exit 1
fi

echo "PASS: discovery auto-connect signaling is wired"

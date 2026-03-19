#!/usr/bin/env bash
set -euo pipefail

plugin_file="src/dsp/streamrtsp_plugin.c"

if [ ! -f "$plugin_file" ]; then
  echo "FAIL: Missing $plugin_file" >&2
  exit 1
fi

if ! rg -q 'set_state\(inst, "waiting_for_sender"\)' "$plugin_file"; then
  echo "FAIL: transient offline failures should transition to waiting_for_sender" >&2
  exit 1
fi

if ! rg -q 'static void maybe_retry_sender\(' "$plugin_file"; then
  echo "FAIL: plugin should include background retry scheduler for waiting sender" >&2
  exit 1
fi

if ! rg -q 'maybe_retry_sender\(inst\);' "$plugin_file"; then
  echo "FAIL: render loop must invoke sender retry scheduler" >&2
  exit 1
fi

echo "PASS: offline retry flow is wired"

#!/usr/bin/env bash
set -euo pipefail

plugin_file="src/dsp/streamrtsp_plugin.c"

if [ ! -f "$plugin_file" ]; then
  echo "FAIL: Missing $plugin_file" >&2
  exit 1
fi

if rg -Fq 'HARD_CODED_RTSP_ENDPOINT' "$plugin_file"; then
  echo "FAIL: temporary hardcoded endpoint override should be removed" >&2
  exit 1
fi

echo "PASS: hardcoded endpoint override removed"

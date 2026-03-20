#!/usr/bin/env bash
set -euo pipefail

plugin_file="src/dsp/streamrtsp_plugin.c"

if [ ! -f "$plugin_file" ]; then
  echo "FAIL: Missing $plugin_file" >&2
  exit 1
fi

create_block="$(awk '/static void\* v2_create_instance/{flag=1} flag{print} /return inst;/{if(flag){exit}}' "$plugin_file")"

if printf '%s' "$create_block" | rg -q 'start_scan\(inst\)'; then
  echo "FAIL: manual-mode startup should not auto-start discovery scan" >&2
  exit 1
fi

if ! printf '%s' "$create_block" | rg -q 'set_state\(inst, "disconnected"\)'; then
  echo "FAIL: startup should initialize in disconnected state" >&2
  exit 1
fi

echo "PASS: startup manual-mode behavior is wired"

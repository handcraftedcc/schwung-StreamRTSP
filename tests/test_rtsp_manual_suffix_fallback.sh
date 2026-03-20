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

if ! rg -q 'strcmp\(key, "manual_suffix"\)' "$plugin_file"; then
  echo "FAIL: plugin must handle manual_suffix parameter" >&2
  exit 1
fi

if ! rg -q 'strcmp\(key, "manual_port"\)' "$plugin_file"; then
  echo "FAIL: plugin must handle manual_port parameter" >&2
  exit 1
fi

if ! rg -q 'strcmp\(key, "manual_path"\)' "$plugin_file"; then
  echo "FAIL: plugin must handle manual_path parameter" >&2
  exit 1
fi

if ! rg -q 'strcmp\(key, "connect_manual"\)' "$plugin_file"; then
  echo "FAIL: plugin must handle connect_manual action" >&2
  exit 1
fi

if ! rg -q 'strcmp\(key, "network_prefix"\)' "$plugin_file"; then
  echo "FAIL: plugin must expose network_prefix status" >&2
  exit 1
fi

if ! rg -q 'strcmp\(key, "manual_suffix"\)' "$plugin_file"; then
  echo "FAIL: plugin must expose manual_suffix status" >&2
  exit 1
fi

if ! rg -q 'IP Suffix:' "$ui_file"; then
  echo "FAIL: UI should expose IP Suffix control" >&2
  exit 1
fi

if ! rg -q 'Port:' "$ui_file"; then
  echo "FAIL: UI should expose Port control" >&2
  exit 1
fi

if ! rg -q 'Path:' "$ui_file"; then
  echo "FAIL: UI should expose Path control" >&2
  exit 1
fi

if ! rg -q "host_module_set_param\\('connect_manual'" "$ui_file"; then
  echo "FAIL: UI should trigger connect_manual action" >&2
  exit 1
fi

if ! rg -q "host_module_set_param\\('manual_path'" "$ui_file"; then
  echo "FAIL: UI should persist manual_path edits" >&2
  exit 1
fi

if ! rg -q "host_module_set_param\\('reset_client'" "$ui_file"; then
  echo "FAIL: UI should trigger reset_client action" >&2
  exit 1
fi

for needle in 'openTextEntry' 'isTextEntryActive' 'handleTextEntryMidi' 'drawTextEntry' 'tickTextEntry'; do
  if ! rg -q "$needle" "$ui_file"; then
    echo "FAIL: UI should integrate shared text-entry API ($needle)" >&2
    exit 1
  fi
done

if ! rg -q 'title:.*IP Suffix' "$ui_file"; then
  echo "FAIL: IP suffix action should open text entry titled for suffix input" >&2
  exit 1
fi

if ! rg -q 'title:.*RTSP Path' "$ui_file"; then
  echo "FAIL: Path action should open text entry titled for RTSP path input" >&2
  exit 1
fi

echo "PASS: manual suffix + port + path UI flow is wired"

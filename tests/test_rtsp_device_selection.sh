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

if ! rg -q 'strcmp\(key, "connect_candidate"\)' "$plugin_file"; then
  echo "FAIL: plugin must support connect_candidate action" >&2
  exit 1
fi

if ! rg -q 'strcmp\(key, "candidate_count"\)' "$plugin_file"; then
  echo "FAIL: plugin must expose candidate_count param" >&2
  exit 1
fi

if ! rg -q 'sscanf\(key, "candidate_%d_name"' "$plugin_file"; then
  echo "FAIL: plugin must expose candidate_<n>_name params" >&2
  exit 1
fi

if ! rg -q 'sscanf\(key, "candidate_%d_url"' "$plugin_file"; then
  echo "FAIL: plugin must expose candidate_<n>_url params" >&2
  exit 1
fi

if ! rg -q "host_module_get_param\\('candidate_count'\\)" "$ui_file"; then
  echo "FAIL: UI should read candidate_count from plugin params" >&2
  exit 1
fi

if ! rg -q "candidate_\\$\\{i\\}_name|candidate_\\$\\{i\\}_url" "$ui_file"; then
  echo "FAIL: UI should read candidate_<n>_name/url params for device list" >&2
  exit 1
fi

if ! rg -q "host_module_set_param\\('connect_candidate'" "$ui_file"; then
  echo "FAIL: UI should connect using selected candidate index" >&2
  exit 1
fi

echo "PASS: candidate device selection is wired"

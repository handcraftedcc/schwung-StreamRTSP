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

echo "PASS: candidate device selection backend is wired"

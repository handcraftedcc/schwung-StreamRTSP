#!/usr/bin/env bash
set -euo pipefail

plugin_file="src/dsp/streamrtsp_plugin.c"
discovery_script="src/runtime/screenstream_discovery.sh"
scan_script="src/runtime/screenstream_scan.sh"
backend_build="scripts/build_rtsp_backend.sh"

for f in "$plugin_file" "$backend_build"; do
  if [ ! -f "$f" ]; then
    echo "FAIL: Missing $f" >&2
    exit 1
  fi
done

if [ ! -x "$discovery_script" ]; then
  echo "FAIL: Missing executable $discovery_script" >&2
  exit 1
fi

if [ ! -x "$scan_script" ]; then
  echo "FAIL: Missing executable $scan_script" >&2
  exit 1
fi

if ! rg -q 'screenstream_discovery\.sh' "$plugin_file"; then
  echo "FAIL: plugin must invoke screenstream_discovery.sh" >&2
  exit 1
fi

if ! rg -q 'discovery\.env' "$plugin_file"; then
  echo "FAIL: plugin must consume discovery result file (discovery.env)" >&2
  exit 1
fi

if ! rg -q 'screenstream_scan\.sh' "$discovery_script"; then
  echo "FAIL: discovery script must include fallback call to screenstream_scan.sh" >&2
  exit 1
fi

if ! rg -q 'MAX_HOSTS=' "$scan_script"; then
  echo "FAIL: subnet scan must be bounded with MAX_HOSTS" >&2
  exit 1
fi

max_hosts_default="$(sed -n 's/^MAX_HOSTS=\"\${MAX_HOSTS:-\([0-9][0-9]*\)}\"/\1/p' "$scan_script" | head -n1)"
if [ -z "${max_hosts_default:-}" ]; then
  echo "FAIL: unable to parse MAX_HOSTS default from $scan_script" >&2
  exit 1
fi

if [ "$max_hosts_default" -lt 128 ]; then
  echo "FAIL: MAX_HOSTS default should cover common LAN ranges (>=128), found $max_hosts_default" >&2
  exit 1
fi

if ! rg -q 'sleep ' "$scan_script"; then
  echo "FAIL: subnet scan should be rate-limited with sleep" >&2
  exit 1
fi

if ! rg -q 'screenstream_discovery\.sh|screenstream_scan\.sh' "$backend_build"; then
  echo "FAIL: build_rtsp_backend.sh must stage discovery helpers" >&2
  exit 1
fi

echo "PASS: RTSP discovery scaffold is wired"

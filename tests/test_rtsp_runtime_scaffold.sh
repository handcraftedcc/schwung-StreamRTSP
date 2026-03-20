#!/usr/bin/env bash
set -euo pipefail

plugin_file="src/dsp/streamrtsp_plugin.c"
build_script="scripts/build.sh"

for f in "$plugin_file" "$build_script"; do
  if [ ! -f "$f" ]; then
    echo "FAIL: Missing $f" >&2
    exit 1
  fi
done

if rg -q 'librespot' "$plugin_file"; then
  echo "FAIL: plugin should not contain librespot-specific supervisor launch logic" >&2
  exit 1
fi

if ! rg -q 'streamrtsp_backend\.sh' "$plugin_file"; then
  echo "FAIL: plugin must launch streamrtsp_backend.sh helper" >&2
  exit 1
fi

for state in scanning connecting buffering streaming reconnecting error disconnected; do
  if ! rg -q "\"$state\"" "$plugin_file"; then
    echo "FAIL: plugin must include RTSP session state '$state'" >&2
    exit 1
  fi
done

for key in connect disconnect scan auto_reconnect connect_last; do
  if ! rg -q "strcmp\(key, \"$key\"\)" "$plugin_file"; then
    echo "FAIL: plugin must handle lifecycle key '$key'" >&2
    exit 1
  fi
done

if ! rg -q 'strcmp\(key, "restart"\)' "$plugin_file"; then
  echo "FAIL: plugin must handle lifecycle key 'restart'" >&2
  exit 1
fi

if ! rg -q 'set_error\(inst, "no endpoint configured"\)' "$plugin_file"; then
  echo "FAIL: restart path should surface explicit error when endpoint is missing" >&2
  exit 1
fi

if ! rg -q 'connect_last requested without saved endpoint; triggering scan' "$plugin_file"; then
  echo "FAIL: connect_last path should log and trigger scan when no saved endpoint exists" >&2
  exit 1
fi

if ! rg -q 'ffmpeg missing on Move' "$plugin_file"; then
  echo "FAIL: plugin should report missing ffmpeg with explicit last_error text" >&2
  exit 1
fi

if ! rg -Fq 'RTSP server unavailable; waiting for sender and scheduling retry' "$plugin_file"; then
  echo "FAIL: plugin should treat 5XX/connect failures as waiting/retry state" >&2
  exit 1
fi

if ! rg -q 'waiting_for_sender' "$plugin_file"; then
  echo "FAIL: plugin should include waiting_for_sender state for transient offline retry" >&2
  exit 1
fi

if ! rg -q 'maybe_retry_sender' "$plugin_file"; then
  echo "FAIL: plugin should schedule reconnect attempts while waiting for sender" >&2
  exit 1
fi

if ! rg -Fq 'RTSP stream has no audio (enable sender audio)' "$plugin_file"; then
  echo "FAIL: plugin should map no-audio backend failures to actionable error text" >&2
  exit 1
fi

if ! rg -q 'src/dsp/streamrtsp_plugin\.c' "$build_script"; then
  echo "FAIL: build script must compile src/dsp/streamrtsp_plugin.c" >&2
  exit 1
fi

echo "PASS: RTSP runtime scaffold is wired"

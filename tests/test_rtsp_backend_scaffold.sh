#!/usr/bin/env bash
set -euo pipefail

backend_build="scripts/build_rtsp_backend.sh"
build_script="scripts/build.sh"
backend_script="src/runtime/streamrtsp_backend.sh"

dockerfile="scripts/Dockerfile"

for f in "$build_script" "$dockerfile"; do
  if [ ! -f "$f" ]; then
    echo "FAIL: Missing $f" >&2
    exit 1
  fi
done

if [ ! -f "$backend_script" ]; then
  echo "FAIL: Missing $backend_script" >&2
  exit 1
fi

if [ ! -x "$backend_build" ]; then
  echo "FAIL: Missing executable $backend_build" >&2
  exit 1
fi

if ! rg -q 'dist/streamrtsp/bin/streamrtsp_backend\.sh' "$backend_build"; then
  echo "FAIL: build_rtsp_backend.sh must stage dist/streamrtsp/bin/streamrtsp_backend.sh" >&2
  exit 1
fi

if ! rg -q './scripts/build_rtsp_backend\.sh' "$build_script"; then
  echo "FAIL: scripts/build.sh must invoke scripts/build_rtsp_backend.sh" >&2
  exit 1
fi

if ! rg -q 'streamrtsp_backend\.sh' "$build_script"; then
  echo "FAIL: build.sh must package streamrtsp backend helper" >&2
  exit 1
fi

if ! rg -q 'ERROR: ffmpeg is required for RTSP ingest' "$backend_script"; then
  echo "FAIL: backend must report missing ffmpeg clearly" >&2
  exit 1
fi

if ! rg -q 'FFMPEG_BIN' "$backend_script"; then
  echo "FAIL: backend should allow explicit ffmpeg binary override via FFMPEG_BIN" >&2
  exit 1
fi

if ! rg -q 'dirname \"\$0\"' "$backend_script"; then
  echo "FAIL: backend should derive module-local ffmpeg path from script directory" >&2
  exit 1
fi

if ! rg -q '\"\$script_dir/ffmpeg\"' "$backend_script"; then
  echo "FAIL: backend should prefer bundled ffmpeg next to streamrtsp_backend.sh" >&2
  exit 1
fi

if ! rg -q '>> \"\$log_path\"' "$backend_script"; then
  echo "FAIL: backend should append startup/runtime errors to log_path when provided" >&2
  exit 1
fi

echo "PASS: RTSP backend scaffold build integration is present"

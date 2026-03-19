#!/usr/bin/env bash
set -euo pipefail

bundle_script="scripts/build_ffmpeg.sh"
build_script="scripts/build.sh"

for f in "$bundle_script" "$build_script"; do
  if [ ! -f "$f" ]; then
    echo "FAIL: Missing $f" >&2
    exit 1
  fi
done

if [ ! -x "$bundle_script" ]; then
  echo "FAIL: Missing executable $bundle_script" >&2
  exit 1
fi

if ! rg -q './scripts/build_ffmpeg\.sh' "$build_script"; then
  echo "FAIL: build.sh must invoke scripts/build_ffmpeg.sh" >&2
  exit 1
fi

if ! rg -q 'linuxarm64' "$bundle_script"; then
  echo "FAIL: ffmpeg bundling should target linuxarm64 artifacts" >&2
  exit 1
fi

if ! rg -q 'FFMPEG_SHA256' "$bundle_script"; then
  echo "FAIL: ffmpeg bundling should verify archive checksum" >&2
  exit 1
fi

if ! rg -q 'dist/streamrtsp/bin/ffmpeg' "$bundle_script"; then
  echo "FAIL: ffmpeg bundling must stage dist/streamrtsp/bin/ffmpeg" >&2
  exit 1
fi

echo "PASS: ffmpeg bundling scaffold is wired"

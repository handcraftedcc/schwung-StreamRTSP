#!/usr/bin/env bash
set -euo pipefail

module_json="src/module.json"
release_json="release.json"
readme="README.md"

if ! command -v jq >/dev/null 2>&1; then
  echo "FAIL: jq is required to run this test" >&2
  exit 1
fi

for f in "$module_json" "$release_json" "$readme"; do
  if [ ! -f "$f" ]; then
    echo "FAIL: Missing $f" >&2
    exit 1
  fi
done

id=$(jq -r '.id' "$module_json")
name=$(jq -r '.name' "$module_json")
abbrev=$(jq -r '.abbrev' "$module_json")
version=$(jq -r '.version' "$release_json")
url=$(jq -r '.download_url' "$release_json")

if [ "$id" != "streamrtsp" ]; then
  echo "FAIL: src/module.json id must be streamrtsp (got: $id)" >&2
  exit 1
fi

if [ "$name" != "StreamRTSP" ]; then
  echo "FAIL: src/module.json name must be StreamRTSP (got: $name)" >&2
  exit 1
fi

if [ "$abbrev" != "RTSP" ]; then
  echo "FAIL: src/module.json abbrev must be RTSP (got: $abbrev)" >&2
  exit 1
fi

if ! printf '%s' "$url" | rg -q "/releases/download/v${version}/streamrtsp-module\.tar\.gz$"; then
  echo "FAIL: release.json download_url must end with /releases/download/v${version}/streamrtsp-module.tar.gz (got: $url)" >&2
  exit 1
fi

if ! rg -q "ScreenStream" "$readme"; then
  echo "FAIL: README.md must mention ScreenStream" >&2
  exit 1
fi

if ! rg -q "RTSP" "$readme"; then
  echo "FAIL: README.md must mention RTSP" >&2
  exit 1
fi

echo "PASS: RTSP scaffold identity is consistent"

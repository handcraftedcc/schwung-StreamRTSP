#!/usr/bin/env bash
set -euo pipefail

script="src/runtime/screenstream_discovery.sh"

if [ ! -f "$script" ]; then
  echo "FAIL: Missing $script" >&2
  exit 1
fi

if ! bash -n "$script"; then
  echo "FAIL: discovery script must be syntactically valid" >&2
  exit 1
fi

echo "PASS: discovery script syntax is valid"

#!/usr/bin/env bash
set -euo pipefail

release_json="release.json"
module_json="src/module.json"
workflow_file=".github/workflows/release.yml"
dockerfile="scripts/Dockerfile"
artifact_name="streamrtsp-module.tar.gz"

if ! command -v jq >/dev/null 2>&1; then
  echo "FAIL: jq is required to run this test" >&2
  exit 1
fi

if [ ! -f "$release_json" ]; then
  echo "FAIL: Missing $release_json" >&2
  exit 1
fi

if [ ! -f "$module_json" ]; then
  echo "FAIL: Missing $module_json" >&2
  exit 1
fi

if [ ! -f "$workflow_file" ]; then
  echo "FAIL: Missing $workflow_file" >&2
  exit 1
fi

if [ ! -f "$dockerfile" ]; then
  echo "FAIL: Missing $dockerfile" >&2
  exit 1
fi

version=$(jq -r '.version' "$release_json")
module_version=$(jq -r '.version' "$module_json")

url=$(jq -r '.download_url' "$release_json")

if [ -z "$version" ] || [ "$version" = "null" ]; then
  echo "FAIL: release.json missing version" >&2
  exit 1
fi

if [ "$module_version" != "$version" ]; then
  echo "FAIL: version mismatch: src/module.json=$module_version release.json=$version" >&2
  exit 1
fi

if ! printf '%s' "$url" | rg -q "^https://github.com/.+/releases/download/v${version}/${artifact_name}$"; then
  echo "FAIL: release.json download_url mismatch: expected .../releases/download/v${version}/${artifact_name} (got: $url)" >&2
  exit 1
fi

if ! rg -q "Verify release\.json metadata" "$workflow_file"; then
  echo "FAIL: release workflow missing release.json verification step" >&2
  exit 1
fi

if ! rg -q "Build module" "$workflow_file"; then
  echo "FAIL: release workflow missing module build step" >&2
  exit 1
fi

if ! rg -q "softprops/action-gh-release@" "$workflow_file"; then
  echo "FAIL: release workflow missing GitHub release publish step" >&2
  exit 1
fi

if ! rg -q "dist/${artifact_name}" "$workflow_file"; then
  echo "FAIL: release workflow must upload dist/${artifact_name}" >&2
  exit 1
fi

if ! rg -q '^[[:space:]]*gcc[[:space:]]*\\?$' "$dockerfile"; then
  echo "FAIL: build Dockerfile must install host gcc for Rust build scripts" >&2
  exit 1
fi

echo "PASS: release metadata is present and release workflow builds and publishes artifacts"
exit 0

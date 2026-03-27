#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

DIST_BIN="$REPO_ROOT/dist/streamrtsp/bin/ffmpeg"
DIST_THIRD_PARTY_DIR="$REPO_ROOT/dist/streamrtsp/THIRD_PARTY"

FFMPEG_BASE_URL="${FFMPEG_BASE_URL:-https://github.com/BtbN/FFmpeg-Builds/releases/download/latest}"
FFMPEG_ASSET="${FFMPEG_ASSET:-ffmpeg-n8.0-latest-linuxarm64-lgpl-8.0.tar.xz}"
FFMPEG_SHA256="${FFMPEG_SHA256:-}"
FFMPEG_CHECKSUMS_URL="${FFMPEG_CHECKSUMS_URL:-$FFMPEG_BASE_URL/checksums.sha256}"
FFMPEG_ARCHIVE_URL="${FFMPEG_ARCHIVE_URL:-$FFMPEG_BASE_URL/$FFMPEG_ASSET}"

CACHE_DIR="${REPO_ROOT}/build/third_party/cache"
ARCHIVE_PATH="$CACHE_DIR/$FFMPEG_ASSET"

if [ "${SKIP_FFMPEG_BUNDLE:-0}" = "1" ]; then
  echo "Skipping ffmpeg bundling (SKIP_FFMPEG_BUNDLE=1)"
  exit 0
fi

sha256_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
  else
    echo "ERROR: neither sha256sum nor shasum is available for checksum verification" >&2
    return 1
  fi
}

resolve_expected_sha() {
  if [ -n "$FFMPEG_SHA256" ]; then
    printf '%s' "$FFMPEG_SHA256"
    return 0
  fi

  checksum_tmp="$(mktemp)"
  curl -L --fail --retry 3 --retry-delay 2 "$FFMPEG_CHECKSUMS_URL" -o "$checksum_tmp"

  expected="$(awk -v asset="$FFMPEG_ASSET" '$0 ~ ("[ *]" asset "$") { print $1; exit }' "$checksum_tmp")"
  rm -f "$checksum_tmp"

  if [ -z "$expected" ]; then
    echo "ERROR: unable to find checksum for $FFMPEG_ASSET in $FFMPEG_CHECKSUMS_URL" >&2
    return 1
  fi

  printf '%s' "$expected"
}

mkdir -p "$CACHE_DIR" "$(dirname "$DIST_BIN")" "$DIST_THIRD_PARTY_DIR"

expected_sha="$(resolve_expected_sha)"

if [ ! -f "$ARCHIVE_PATH" ] || [ "$(sha256_file "$ARCHIVE_PATH")" != "$expected_sha" ]; then
  echo "Downloading bundled ffmpeg archive..."
  curl -L --fail --retry 3 --retry-delay 2 "$FFMPEG_ARCHIVE_URL" -o "$ARCHIVE_PATH"
fi

actual_sha="$(sha256_file "$ARCHIVE_PATH")"
if [ "$actual_sha" != "$expected_sha" ]; then
  echo "ERROR: ffmpeg archive checksum mismatch" >&2
  echo "  expected: $expected_sha" >&2
  echo "  actual:   $actual_sha" >&2
  exit 1
fi

extract_dir="$(mktemp -d)"
cleanup() {
  rm -rf "$extract_dir"
}
trap cleanup EXIT

tar -xf "$ARCHIVE_PATH" -C "$extract_dir"

source_ffmpeg="$(find "$extract_dir" -type f -path '*/bin/ffmpeg' | head -n1)"
if [ -z "$source_ffmpeg" ] || [ ! -f "$source_ffmpeg" ]; then
  echo "ERROR: ffmpeg binary not found in extracted archive" >&2
  exit 1
fi

cp "$source_ffmpeg" "$DIST_BIN"
chmod +x "$DIST_BIN"

license_file="$(find "$extract_dir" -type f -name 'LICENSE.txt' | head -n1)"
if [ -n "$license_file" ] && [ -f "$license_file" ]; then
  cp "$license_file" "$DIST_THIRD_PARTY_DIR/ffmpeg-LICENSE.txt"
fi

cat > "$DIST_THIRD_PARTY_DIR/ffmpeg-bundle.txt" <<EOF_FFMPEG_BUNDLE
source_url=$FFMPEG_ARCHIVE_URL
archive=$FFMPEG_ASSET
sha256=$expected_sha
EOF_FFMPEG_BUNDLE

echo "Bundled ffmpeg staged:"
echo "  source: $FFMPEG_ARCHIVE_URL"
echo "  output: $DIST_BIN"

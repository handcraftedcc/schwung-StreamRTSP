#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

DIST_BIN="$REPO_ROOT/dist/streamrtsp/bin/ffmpeg"
DIST_THIRD_PARTY_DIR="$REPO_ROOT/dist/streamrtsp/THIRD_PARTY"

CROSS_PREFIX="${CROSS_PREFIX:-aarch64-linux-gnu-}"
FFMPEG_VERSION="${FFMPEG_VERSION:-8.0}"
FFMPEG_SOURCE_ARCHIVE="ffmpeg-${FFMPEG_VERSION}.tar.xz"
FFMPEG_SOURCE_URL="${FFMPEG_SOURCE_URL:-https://ffmpeg.org/releases/${FFMPEG_SOURCE_ARCHIVE}}"
FFMPEG_SOURCE_SHA256="${FFMPEG_SOURCE_SHA256:-b2751fccb6cc4c77708113cd78b561059b6fa904b24162fa0be2d60273d27b8e}"

CACHE_DIR="$REPO_ROOT/build/third_party/cache"
ARCHIVE_PATH="$CACHE_DIR/$FFMPEG_SOURCE_ARCHIVE"
WORK_DIR="$REPO_ROOT/build/third_party/ffmpeg"
SRC_ROOT="$WORK_DIR/src"
BUILD_ROOT="$WORK_DIR/build"
INSTALL_ROOT="$WORK_DIR/install"
STAMP_FILE="$WORK_DIR/.build-stamp"
SOURCE_DIR="$SRC_ROOT/ffmpeg-${FFMPEG_VERSION}"

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

required_tools=(
  "${CROSS_PREFIX}gcc"
  "${CROSS_PREFIX}strip"
  make
  tar
  curl
)
for tool in "${required_tools[@]}"; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "ERROR: missing required build tool: $tool" >&2
    exit 1
  fi
done

FFMPEG_CONFIGURE_FLAGS=(
  --prefix="$INSTALL_ROOT"
  --arch=aarch64
  --target-os=linux
  --enable-cross-compile
  --cross-prefix="$CROSS_PREFIX"
  --cc="${CROSS_PREFIX}gcc"
  --strip="${CROSS_PREFIX}strip"
  --disable-shared
  --enable-static
  --disable-doc
  --disable-debug
  --enable-small
  --disable-autodetect
  --disable-ffplay
  --disable-ffprobe
  --disable-devices
  --disable-indevs
  --disable-outdevs
  --disable-bsfs
  --disable-filters
  --enable-filter=aresample
  --enable-filter=anull
  --disable-demuxers
  --enable-demuxer=rtsp
  --enable-demuxer=rtp
  --enable-demuxer=sdp
  --disable-muxers
  --enable-muxer=pcm_s16le
  --disable-protocols
  --enable-protocol=file
  --enable-protocol=pipe
  --enable-protocol=tcp
  --enable-protocol=udp
  --enable-protocol=rtp
  --disable-encoders
  --enable-encoder=pcm_s16le
  --disable-decoders
  --enable-decoder=aac
  --enable-decoder=aac_latm
  --enable-decoder=mp3
  --enable-decoder=opus
  --enable-decoder=vorbis
  --enable-decoder=flac
  --enable-decoder=pcm_alaw
  --enable-decoder=pcm_mulaw
  --enable-decoder=pcm_s16le
  --enable-decoder=pcm_s24le
  --enable-decoder=pcm_f32le
)

build_signature="$(
  {
    printf '%s\n' "$FFMPEG_VERSION" "$FFMPEG_SOURCE_SHA256" "$FFMPEG_SOURCE_URL" "$CROSS_PREFIX"
    printf '%s\n' "${FFMPEG_CONFIGURE_FLAGS[@]}"
  } | shasum -a 256 | awk '{print $1}'
)"

mkdir -p "$CACHE_DIR" "$(dirname "$DIST_BIN")" "$DIST_THIRD_PARTY_DIR" "$SRC_ROOT" "$BUILD_ROOT"

if [ ! -f "$ARCHIVE_PATH" ] || [ "$(sha256_file "$ARCHIVE_PATH")" != "$FFMPEG_SOURCE_SHA256" ]; then
  echo "Downloading FFmpeg source..."
  curl -L --fail --retry 3 --retry-delay 2 "$FFMPEG_SOURCE_URL" -o "$ARCHIVE_PATH"
fi

actual_archive_sha="$(sha256_file "$ARCHIVE_PATH")"
if [ "$actual_archive_sha" != "$FFMPEG_SOURCE_SHA256" ]; then
  echo "ERROR: FFmpeg source checksum mismatch" >&2
  echo "  expected: $FFMPEG_SOURCE_SHA256" >&2
  echo "  actual:   $actual_archive_sha" >&2
  exit 1
fi

if [ ! -x "$INSTALL_ROOT/bin/ffmpeg" ] || [ ! -f "$STAMP_FILE" ] || [ "$(cat "$STAMP_FILE")" != "$build_signature" ]; then
  echo "Building minimal FFmpeg from source..."
  rm -rf "$SOURCE_DIR" "$BUILD_ROOT" "$INSTALL_ROOT"
  mkdir -p "$SRC_ROOT" "$BUILD_ROOT" "$INSTALL_ROOT"

  tar -xf "$ARCHIVE_PATH" -C "$SRC_ROOT"
  cd "$SOURCE_DIR"
  ./configure "${FFMPEG_CONFIGURE_FLAGS[@]}"
  make -j"$(nproc)"
  make install

  printf '%s\n' "$build_signature" > "$STAMP_FILE"
  cd "$REPO_ROOT"
else
  echo "Using cached minimal FFmpeg build."
fi

source_ffmpeg="$INSTALL_ROOT/bin/ffmpeg"
if [ ! -x "$source_ffmpeg" ]; then
  echo "ERROR: ffmpeg binary missing after build: $source_ffmpeg" >&2
  exit 1
fi

cp "$source_ffmpeg" "$DIST_BIN"
"${CROSS_PREFIX}strip" "$DIST_BIN" || true
chmod +x "$DIST_BIN"

if [ -f "$SOURCE_DIR/COPYING.LGPLv2.1" ]; then
  cp "$SOURCE_DIR/COPYING.LGPLv2.1" "$DIST_THIRD_PARTY_DIR/ffmpeg-LICENSE.txt"
elif [ -f "$SOURCE_DIR/COPYING.GPLv2" ]; then
  cp "$SOURCE_DIR/COPYING.GPLv2" "$DIST_THIRD_PARTY_DIR/ffmpeg-LICENSE.txt"
fi

cat > "$DIST_THIRD_PARTY_DIR/ffmpeg-bundle.txt" <<EOF_FFMPEG_BUNDLE
source_url=$FFMPEG_SOURCE_URL
archive=$FFMPEG_SOURCE_ARCHIVE
source_sha256=$FFMPEG_SOURCE_SHA256
build_signature=$build_signature
configure_flags=${FFMPEG_CONFIGURE_FLAGS[*]}
EOF_FFMPEG_BUNDLE

echo "Bundled minimal ffmpeg staged:"
echo "  source: $FFMPEG_SOURCE_URL"
echo "  output: $DIST_BIN"
echo "  size_bytes: $(wc -c < "$DIST_BIN" | tr -d ' ')"

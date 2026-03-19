#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -lt 2 ]; then
  echo "usage: $0 <fifo_path> <rtsp_url> [log_path]" >&2
  exit 2
fi

fifo_path="$1"
rtsp_url="$2"
log_path="${3:-}"
script_dir="$(cd "$(dirname "$0")" && pwd)"
if [ -n "${FFMPEG_BIN:-}" ]; then
  ffmpeg_bin="$FFMPEG_BIN"
elif [ -x "$script_dir/ffmpeg" ]; then
  ffmpeg_bin="$script_dir/ffmpeg"
else
  ffmpeg_bin="ffmpeg"
fi

log_error() {
  local msg="$1"
  echo "$msg" >&2
  if [ -n "$log_path" ]; then
    printf '%s\n' "$msg" >> "$log_path"
  fi
}

if [ -z "$fifo_path" ] || [ -z "$rtsp_url" ]; then
  log_error "ERROR: fifo path and rtsp url are required"
  exit 2
fi

if [[ "$ffmpeg_bin" == */* ]]; then
  if [ ! -x "$ffmpeg_bin" ]; then
    log_error "ERROR: ffmpeg is required for RTSP ingest"
    exit 127
  fi
else
  if ! command -v "$ffmpeg_bin" >/dev/null 2>&1; then
    log_error "ERROR: ffmpeg is required for RTSP ingest"
    exit 127
  fi
fi

ffmpeg_cmd=(
  "$ffmpeg_bin"
  -hide_banner
  -nostats
  -loglevel warning
  -rtsp_transport tcp
  -i "$rtsp_url"
  -map 0:a:0?
  -vn
  -sn
  -dn
  -ac 2
  -ar 44100
  -f s16le
  pipe:1
)

if [ -n "$log_path" ]; then
  "${ffmpeg_cmd[@]}" > "$fifo_path" 2>> "$log_path"
else
  "${ffmpeg_cmd[@]}" > "$fifo_path"
fi

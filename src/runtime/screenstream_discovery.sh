#!/usr/bin/env bash
set -euo pipefail

CACHE_DIR="${1:-/data/UserData/move-anything/cache/streamrtsp}"
OUT_FILE="$CACHE_DIR/discovery.env"
SCAN_FILE="$CACHE_DIR/scan.env"
LAST_SENDER_FILE="$CACHE_DIR/last_sender.env"
TMP_FILE="${OUT_FILE}.tmp.$$"
DISCOVERY_WINDOW_SECONDS="${DISCOVERY_WINDOW_SECONDS:-12}"
DISCOVERY_RETRY_DELAY_SECONDS="${DISCOVERY_RETRY_DELAY_SECONDS:-1}"
MAX_ARP_FALLBACK_CANDIDATES="${MAX_ARP_FALLBACK_CANDIDATES:-12}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCAN_SCRIPT="$SCRIPT_DIR/screenstream_scan.sh"

mkdir -p "$CACHE_DIR"

declare -a CANDIDATE_NAMES=()
declare -a CANDIDATE_URLS=()
RESOLVED_NAME=""
RESOLVED_URL=""

add_candidate() {
  local name="$1"
  local url="$2"
  local i

  [ -n "$url" ] || return 0
  for i in "${!CANDIDATE_URLS[@]}"; do
    if [ "${CANDIDATE_URLS[$i]}" = "$url" ]; then
      return 0
    fi
  done

  CANDIDATE_NAMES+=("$name")
  CANDIDATE_URLS+=("$url")
}

discover_prefix() {
  local ip=""
  ip="$(ip route get 1.1.1.1 2>/dev/null | awk '{for (i=1;i<=NF;i++) if ($i=="src") {print $(i+1); exit}}')"
  if [ -z "$ip" ]; then
    ip="$(hostname -I 2>/dev/null | awk '{print $1}')"
  fi
  if printf '%s' "$ip" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$'; then
    printf '%s' "$ip" | awk -F. '{printf "%s.%s.%s", $1,$2,$3}'
    return 0
  fi
  printf '192.168.0'
}

# Tier 1: mDNS/DNS-SD (if available)
if command -v avahi-browse >/dev/null 2>&1; then
  while IFS=';' read -r kind _ _ svc_name _ _ host addr port _; do
    endpoint_host=""
    [ "$kind" = "=" ] || continue
    [ -n "$port" ] || continue

    if [ -n "${addr:-}" ] && [ "$addr" != "(null)" ]; then
      endpoint_host="$addr"
    elif [ -n "${host:-}" ] && [ "$host" != "(null)" ]; then
      endpoint_host="$host"
    fi

    [ -n "$endpoint_host" ] || continue
    add_candidate "${svc_name:-ScreenStream Sender}" "rtsp://${endpoint_host}:${port}/"
  done < <(avahi-browse -rt _rtsp._tcp 2>/dev/null || true)
fi

# Tier 2: last known sender identity (candidate only; do not auto-resolve)
if [ -f "$LAST_SENDER_FILE" ]; then
  last_endpoint="$(awk -F= '$1=="endpoint"{print $2; exit}' "$LAST_SENDER_FILE" 2>/dev/null || true)"
  if [ -n "$last_endpoint" ]; then
    add_candidate "Last Sender" "$last_endpoint"
  fi
fi

# Tier 3: bounded subnet scan fallback
if [ -z "$RESOLVED_URL" ] && [ -x "$SCAN_SCRIPT" ]; then
  start_epoch="$(date +%s)"
  while [ -z "$RESOLVED_URL" ]; do
    "$SCAN_SCRIPT" "$CACHE_DIR" || true
    if [ -f "$SCAN_FILE" ]; then
      scan_count="$(awk -F= '$1=="count"{print $2; exit}' "$SCAN_FILE" 2>/dev/null || echo 0)"
      if [ "${scan_count:-0}" -gt 0 ]; then
        for i in $(seq 0 $((scan_count - 1))); do
          name="$(awk -F= -v i="$i" '$1==("candidate_" i "_name"){print $2; exit}' "$SCAN_FILE" 2>/dev/null || true)"
          url="$(awk -F= -v i="$i" '$1==("candidate_" i "_url"){print $2; exit}' "$SCAN_FILE" 2>/dev/null || true)"
          [ -n "$url" ] || continue
          add_candidate "${name:-Device $((i + 1))}" "$url"
        done
        break
      fi
    fi

    now_epoch="$(date +%s)"
    if [ $((now_epoch - start_epoch)) -ge "$DISCOVERY_WINDOW_SECONDS" ]; then
      break
    fi
    sleep "$DISCOVERY_RETRY_DELAY_SECONDS"
  done
fi

# Tier 4: fallback candidate list from active LAN neighbors (for manual selection)
if [ "${#CANDIDATE_URLS[@]}" -eq 0 ] && [ -f /proc/net/arp ]; then
  prefix="$(discover_prefix)"
  count=0
  while IFS= read -r host; do
    [ -n "$host" ] || continue
    add_candidate "Host ${host} /screen" "rtsp://${host}:8554/screen"
    add_candidate "Host ${host} /screenlive" "rtsp://${host}:8554/screenlive"
    count=$((count + 1))
    if [ "$count" -ge "$MAX_ARP_FALLBACK_CANDIDATES" ]; then
      break
    fi
  done < <(
    awk 'NR>1 && $3=="0x2" {print $1}' /proc/net/arp 2>/dev/null \
      | grep -E "^${prefix//./\\.}\\.[0-9]+$" \
      | sort -u
  )
fi

{
  if [ -n "$RESOLVED_URL" ]; then
    printf 'resolved_name=%s\n' "$RESOLVED_NAME"
    printf 'resolved_url=%s\n' "$RESOLVED_URL"
  fi
  printf 'count=%d\n' "${#CANDIDATE_URLS[@]}"
  for i in "${!CANDIDATE_URLS[@]}"; do
    printf 'candidate_%d_name=%s\n' "$i" "${CANDIDATE_NAMES[$i]}"
    printf 'candidate_%d_url=%s\n' "$i" "${CANDIDATE_URLS[$i]}"
  done
} > "$TMP_FILE"

mv "$TMP_FILE" "$OUT_FILE"

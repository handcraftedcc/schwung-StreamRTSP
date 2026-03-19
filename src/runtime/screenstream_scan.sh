#!/usr/bin/env bash
set -euo pipefail

CACHE_DIR="${1:-/data/UserData/move-anything/cache/streamrtsp}"
OUT_FILE="$CACHE_DIR/scan.env"
TMP_FILE="${OUT_FILE}.tmp.$$"

# Keep fallback bounded but wide enough for common DHCP ranges (e.g. .100-.199).
MAX_HOSTS="${MAX_HOSTS:-130}"
SCAN_SLEEP_SECONDS="${SCAN_SLEEP_SECONDS:-0}"
PORT_CANDIDATES="${PORT_CANDIDATES:-8554 554}"

mkdir -p "$CACHE_DIR"

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
  printf '192.168.1'
}

discover_host_octet() {
  local ip=""
  local octet=100
  ip="$(ip route get 1.1.1.1 2>/dev/null | awk '{for (i=1;i<=NF;i++) if ($i=="src") {print $(i+1); exit}}')"
  if [ -z "$ip" ]; then
    ip="$(hostname -I 2>/dev/null | awk '{print $1}')"
  fi
  if printf '%s' "$ip" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$'; then
    octet="$(printf '%s' "$ip" | awk -F. '{print $4}')"
  fi
  if [ "${octet:-0}" -lt 2 ] || [ "${octet:-255}" -gt 254 ]; then
    octet=100
  fi
  printf '%s' "$octet"
}

prefix="$(discover_prefix)"
local_octet="$(discover_host_octet)"
count=0
body_file="${TMP_FILE}.body"
: > "$body_file"

probe_host_port() {
  local host="$1"
  local port="$2"
  local pid
  local i

  if ! command -v bash >/dev/null 2>&1; then
    return 1
  fi

  # BusyBox nc on Move does not support timeout/scan flags. Use bash /dev/tcp
  # with a short watchdog loop so probes stay bounded.
  bash -c "cat < /dev/null > /dev/tcp/${host}/${port}" >/dev/null 2>&1 &
  pid=$!

  for i in 1 2 3 4 5; do
    if ! kill -0 "$pid" 2>/dev/null; then
      wait "$pid"
      return $?
    fi
    sleep 0.1
  done

  kill "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
  return 1
}

scan_host_list() {
while IFS= read -r host; do
  found=""
  [ -n "$host" ] || continue
  for port in $PORT_CANDIDATES; do
    if probe_host_port "$host" "$port"; then
      printf 'candidate_%d_name=RTSP %s:%s /screen\n' "$count" "$host" "$port" >> "$body_file"
      printf 'candidate_%d_url=rtsp://%s:%s/screen\n' "$count" "$host" "$port" >> "$body_file"
      count=$((count + 1))
      printf 'candidate_%d_name=RTSP %s:%s /screenlive\n' "$count" "$host" "$port" >> "$body_file"
      printf 'candidate_%d_url=rtsp://%s:%s/screenlive\n' "$count" "$host" "$port" >> "$body_file"
      count=$((count + 1))
      found="1"
      break
    fi
  done
  sleep "$SCAN_SLEEP_SECONDS"
  if [ -n "$found" ]; then
    continue
  fi
done
}

host_file="${TMP_FILE}.hosts"
: > "$host_file"

append_host() {
  local host="$1"
  [ -n "$host" ] || return 0
  if ! printf '%s' "$host" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$'; then
    return 0
  fi
  printf '%s\n' "$host" >> "$host_file"
}

append_suffix_host() {
  local suffix="$1"
  if [ "$suffix" -lt 2 ] || [ "$suffix" -gt 254 ]; then
    return 0
  fi
  append_host "${prefix}.${suffix}"
}

# Prefer known active neighbors first.
if [ -f /proc/net/arp ]; then
  while IFS= read -r host; do
    append_host "$host"
  done < <(
    awk 'NR>1 && $3=="0x2" {print $1}' /proc/net/arp 2>/dev/null \
      | grep -E "^${prefix//./\\.}\\.[0-9]+$" \
      | sort -u
  )
fi

# Supplemental bounded range scan so non-ARP devices (e.g., .233) are still discovered.
for i in $(seq $((local_octet - 32)) $((local_octet + 32))); do
  append_suffix_host "$i"
done
for i in $(seq 200 254); do
  append_suffix_host "$i"
done
for i in $(seq 2 199); do
  append_suffix_host "$i"
done

candidate_hosts="$(
  awk -v max="$MAX_HOSTS" '!seen[$0]++ {print; if (++n >= max) exit}' "$host_file"
)"
scan_host_list <<EOF_HOSTS
$candidate_hosts
EOF_HOSTS
rm -f "$host_file"

{
  printf 'count=%d\n' "$count"
  cat "$body_file"
} > "$TMP_FILE"

mv "$TMP_FILE" "$OUT_FILE"
rm -f "$body_file"

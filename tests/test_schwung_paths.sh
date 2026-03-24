#!/usr/bin/env bash
set -euo pipefail

plugin_file="src/dsp/streamrtsp_plugin.c"
ui_file="src/ui.js"
install_file="scripts/install.sh"
runtime_discovery="src/runtime/screenstream_discovery.sh"
runtime_scan="src/runtime/screenstream_scan.sh"
runtime_event="src/runtime/streamrtsp_event.sh"

if ! rg -q '/data/UserData/schwung/modules/sound_generators/streamrtsp' "$plugin_file"; then
  echo "FAIL: plugin module log default path should use /data/UserData/schwung" >&2
  exit 1
fi

if ! rg -q '/data/UserData/schwung/cache/streamrtsp' "$plugin_file"; then
  echo "FAIL: plugin cache default path should use /data/UserData/schwung" >&2
  exit 1
fi

if ! rg -q '/data/UserData/schwung/shared/' "$ui_file"; then
  echo "FAIL: UI shared imports should use /data/UserData/schwung" >&2
  exit 1
fi

if ! rg -q '/data/UserData/schwung/modules/sound_generators' "$install_file"; then
  echo "FAIL: install target path should use /data/UserData/schwung" >&2
  exit 1
fi

if ! rg -q '/data/UserData/schwung/display-server' "$install_file"; then
  echo "FAIL: install UI restart path should use /data/UserData/schwung/display-server" >&2
  exit 1
fi

if ! rg -q '/data/UserData/schwung/cache/streamrtsp' "$runtime_discovery"; then
  echo "FAIL: discovery default cache path should use /data/UserData/schwung" >&2
  exit 1
fi

if ! rg -q '/data/UserData/schwung/cache/streamrtsp' "$runtime_scan"; then
  echo "FAIL: scan default cache path should use /data/UserData/schwung" >&2
  exit 1
fi

if ! rg -q '/data/UserData/schwung/cache/streamrtsp-nowplaying.env' "$runtime_event"; then
  echo "FAIL: runtime event state path should use /data/UserData/schwung" >&2
  exit 1
fi

echo "PASS: Schwung path migration is wired"

# Move Everything - StreamRTSP

StreamRTSP is a Sound Generator module for [Move Everything](https://github.com/charlesvestal/move-everything) on Ableton Move.

It is being built as a local-only Android ScreenStream RTSP audio receiver:
- RTSP transport for v1
- local network only
- discovery-first workflow (no manual IP in normal use)
- quality/stability over low latency

## Current Status

This repository is in active migration from older scaffold naming to StreamRTSP.
Core packaging/build/runtime file names now use `streamrtsp` naming.

## Build

```bash
./scripts/build.sh
```

Build output:
- `dist/streamrtsp/`
- `dist/streamrtsp-module.tar.gz`

Build pipeline notes:
- Bundles ARM64 `ffmpeg` into `dist/streamrtsp/bin/ffmpeg`
- Uses pinned checksum-verified archive from BtbN FFmpeg Builds
- Set `SKIP_FFMPEG_BUNDLE=1` to skip bundling for local experiments

## Install

```bash
./scripts/install.sh
```

Default install target:
- Device: `root@move.local`
- Path: `/data/UserData/move-anything/modules/sound_generators/streamrtsp/`

## Project Layout

- `scripts/`: build and install pipeline
- `src/module.json`: module metadata
- `src/ui.js`: module UI behavior
- `src/dsp/streamrtsp_plugin.c`: DSP/runtime supervisor and audio path
- `src/runtime/streamrtsp_event.sh`: runtime event metadata hook
- `tests/`: scaffold and runtime test scripts
- `.github/workflows/release.yml`: tag-based release workflow

## License

MIT

# Schwung - StreamRTSP

StreamRTSP is a Sound Generator module for [Schwung](https://github.com/charlesvestal/schwung) on Ableton Move.

It is a local-only Android ScreenStream RTSP audio receiver:
- RTSP transport for v1
- local network only
- manual endpoint input workflow (IP suffix, port, path)
- quality/stability over low latency

Recommended use with [ScreenStream](https://play.google.com/store/apps/details?id=info.dvkr.screenstream&hl=en_US) on android - make sure to set protocol to RTSP and enable "device audio" under audio parameters.
For windows you can use this [RTSP python streaming script](https://github.com/handcraftedcc/RTSPWindowsAudioStreamScript) (check readme for how to get it running).

## Getting Started

1. Open your RTSP server app (for example ScreenStream) and note the server endpoint.
2. In StreamRTSP, enter:
   - IP suffix: the last part of the IP (`233` for `192.168.0.233`)
   - Port: the server port (`8554` in `:8554`)
   - Path: the stream path (`screen` or `screenlive`, without leading `/`)
3. Press `Connect` and wait for audio.

## Build

```bash
./scripts/build.sh
```

Build output:
- `dist/streamrtsp/`
- `dist/streamrtsp-module.tar.gz`

Build pipeline notes:
- Builds and bundles a minimal ARM64 `ffmpeg` into `dist/streamrtsp/bin/ffmpeg`
- Compiles from pinned FFmpeg source with only RTSP + required audio decode/output components
- Set `SKIP_FFMPEG_BUNDLE=1` to skip bundling for local experiments

## Install

```bash
./scripts/install.sh
```

Default install target:
- Device: `root@move.local`
- Path: `/data/UserData/schwung/modules/sound_generators/streamrtsp/`

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

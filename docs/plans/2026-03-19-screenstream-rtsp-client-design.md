# ScreenStream RTSP Client Design

## Goal
Build a Move Everything sound generator module that receives local Android ScreenStream RTSP audio and plays it on Move with quality/stability prioritized over latency.

## Constraints From Requirements + Existing Repo
- Keep module structure aligned with Move module conventions (`module.json`, `ui.js`, `ui_chain.js`, `dsp.so`, build/install scripts).
- Preserve the proven script/workflow pattern used in this repo and the AirPlay reference module; update it, do not replace it wholesale.
- Keep lifecycle robustness from current StreamRTSP DSP runtime: subprocess supervision, ring buffer feeding, graceful teardown, and recovery state machine.
- UX priority is local auto-discovery and reconnect to last device; manual URL is fallback-only.
- RTSP-only for v1; no WebRTC/Chromecast/cloud dependencies.

## Approaches Considered

### Approach A: In-plugin `libav*` decode (C API, no helper process)
- Pros: tight integration, direct control over decode/buffer/drift handling, fewer shell dependencies at runtime.
- Cons: highest implementation complexity/risk, significant cross-build/packaging burden, most invasive refactor from current proven subprocess model.

### Approach B (Recommended): FFmpeg helper process + existing DSP ring-buffer architecture
- Pros: best fit to current module architecture (already process-supervised + FIFO PCM ingest), fastest path to reliable v1, minimal disruption to build/release layout.
- Cons: external helper lifecycle to manage; discovery and session orchestration still need dedicated scripts/state glue.

### Approach C: GStreamer helper process
- Pros: strong RTSP graph flexibility, easy audio-only pipeline with `-vn` equivalent graph behavior.
- Cons: larger runtime dependency surface and likely less predictable packaging on Move than FFmpeg CLI flow.

## Recommendation
Use Approach B: keep the current DSP runtime architecture and swap backend responsibilities from `librespot` to RTSP audio ingest (`ffmpeg` helper first). This preserves the module’s stable lifecycle model and allows discovery/session/audio-quality work to be layered in phases.

## Proposed Architecture

### 1) DSP Runtime Core (existing pattern retained)
- Keep C plugin as the source of truth for lifecycle state, ring buffer, underrun handling, and host param bridge.
- Replace Spotify-specific supervisor logic with RTSP session lifecycle (`distreamrtsped`, `scanning`, `connecting`, `buffering`, `streaming`, `reconnecting`, `error`).
- Keep callback-safe behavior: no network I/O in `render_block`, always silence-safe when unavailable.

### 2) RTSP Backend Wrapper
- Add a backend launcher script that:
  - validates endpoint
  - starts FFmpeg in audio-only mode
  - maps first audio track
  - drops video as early as possible
  - outputs PCM to FIFO for DSP ingest
- Keep args explicit and sanitized; no unsafe shell interpolation.

### 3) Discovery Layer (tiered)
- Tier 1: Zeroconf/mDNS browse where available.
- Tier 2: last-known sender identity reconnect (hostname/service identity preferred over raw IP).
- Tier 3: bounded subnet probing for RTSP candidates.
- Discovery runs outside audio callback and writes bounded candidate/state artifacts for DSP/UI consumption.

### 4) UI and Persistence
- UI presents normal flow first: scan/list/connect/distreamrtsp/auto-reconnect.
- Manual URL remains advanced fallback only.
- Persist required settings: auto reconnect, last sender identity, gain, mono sum, buffer mode, headroom.

### 5) Build/Release Contract
- Keep `scripts/build.sh`, `scripts/install.sh`, `scripts/Dockerfile` structure and behavior shape.
- Add/update `.github/workflows/release.yml` to match the proven release contract (version checks + build + asset publish).
- Keep tests that enforce metadata and workflow integrity; extend with RTSP-specific scaffold/lifecycle checks.

## Risk Notes and Mitigation
- FFmpeg packaging risk on target:
  - mitigate with a deterministic helper build/staging step and explicit version pinning.
- Discovery variability across Android sender builds:
  - mitigate with tiered fallback and bounded subnet probing.
- Long-session drift/stability:
  - mitigate with ring-buffer health policy + configurable buffer modes first; only add adaptive compensation if observed in soak tests.

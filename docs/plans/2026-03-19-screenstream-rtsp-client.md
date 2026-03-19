# ScreenStream RTSP Client Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Convert this module into a local-only RTSP audio receiver for Android ScreenStream with automatic discovery, robust reconnect behavior, and quality-first playback.

**Architecture:** Keep the proven StreamRTSP/AirPlay shape (DSP-supervised subprocess + FIFO + ring buffer + simple menu UI + script-driven build/install). Replace Spotify-specific runtime behavior with RTSP discovery/session/backend components while preserving lifecycle safety and release pipeline reliability.

**Tech Stack:** C (Move DSP plugin API v2), Bash helper scripts, JSON metadata/help docs, GitHub Actions release workflow, shell-based test scripts.

**Coverage Note:** This plan includes explicit tasks/tests for drift compensation, security hardening, edge-case error handling, required status field visibility, and long-session soak/lifecycle validation.

---

### Task 1: Freeze release/scaffold contract before behavior changes

**Files:**
- Create: `tests/test_rtsp_scaffold_identity.sh`
- Modify: `tests/test_release_metadata.sh`
- Modify: `release.json`

**Step 1: Write the failing test**

Create `tests/test_rtsp_scaffold_identity.sh` to assert:
- module id/name/abbrev align with RTSP module naming
- release artifact uses RTSP artifact naming
- docs mention RTSP/ScreenStream (not Spotify-first language)

**Step 2: Run test to verify it fails**

Run: `bash tests/test_rtsp_scaffold_identity.sh`
Expected: FAIL because repository still references StreamRTSP identity.

**Step 3: Implement minimal metadata updates**

- Update `release.json` naming/URL contract for RTSP artifact.
- Update `tests/test_release_metadata.sh` expected artifact name and workflow checks (keep same style).

**Step 4: Run tests to verify pass/fail transition**

Run: `bash tests/test_rtsp_scaffold_identity.sh`
Run: `bash tests/test_release_metadata.sh`
Expected: identity test may still fail until module/docs are updated in later tasks; release metadata test should pass once workflow exists.

**Step 5: Commit**

```bash
git add tests/test_rtsp_scaffold_identity.sh tests/test_release_metadata.sh release.json
git commit -m "test: establish rtsp scaffold and release metadata contract"
```

### Task 2: Add/align GitHub release workflow without rewriting build logic

**Files:**
- Create: `.github/workflows/release.yml`

**Step 1: Add failing expectation (if missing)**

Run: `bash tests/test_release_metadata.sh`
Expected: FAIL with missing `.github/workflows/release.yml`.

**Step 2: Implement workflow using proven pattern**

Create `.github/workflows/release.yml` by adapting the AirPlay/StreamRTSP contract:
- trigger on `v*` tags
- verify tag version matches `src/module.json`
- verify `release.json` version and download URL
- run Dockerized build via `scripts/build.sh`
- publish `dist/<rtsp-artifact>.tar.gz` with `softprops/action-gh-release`

**Step 3: Re-run release metadata test**

Run: `bash tests/test_release_metadata.sh`
Expected: PASS.

**Step 4: Commit**

```bash
git add .github/workflows/release.yml
git commit -m "ci: add release workflow aligned with existing module contract"
```

### Task 3: Convert module identity/docs/help to RTSP receiver

**Files:**
- Modify: `README.md`
- Modify: `src/module.json`
- Modify: `src/help.json`
- Modify: `src/ui.js`
- Modify: `src/ui_chain.js` (if imports/labels need alignment)

**Step 1: Update failing identity expectations**

Ensure `tests/test_rtsp_scaffold_identity.sh` checks:
- `src/module.json` has RTSP receiver identity and `component_type: sound_generator`
- README/help reference ScreenStream RTSP flow

**Step 2: Run failing test**

Run: `bash tests/test_rtsp_scaffold_identity.sh`
Expected: FAIL before docs/metadata edits.

**Step 3: Implement minimal identity conversion**

- Keep module shape and capabilities structure.
- Update text/UI labels/statuses from Spotify-specific wording to RTSP receiver wording.
- Keep `chain_params` style and defaults pattern consistent with existing module.

**Step 4: Re-run identity + release tests**

Run: `bash tests/test_rtsp_scaffold_identity.sh`
Run: `bash tests/test_release_metadata.sh`
Expected: PASS.

**Step 5: Commit**

```bash
git add README.md src/module.json src/help.json src/ui.js src/ui_chain.js
git commit -m "chore: convert module identity and docs to screenstream rtsp receiver"
```

### Task 4: Introduce RTSP backend build/staging script (pattern-matched to existing scripts)

**Files:**
- Create: `scripts/build_rtsp_backend.sh`
- Modify: `scripts/build.sh`
- Modify: `scripts/Dockerfile`

**Step 1: Write failing scaffold test**

Create/extend a test (for example `tests/test_rtsp_backend_scaffold.sh`) to assert:
- backend build script exists
- `scripts/build.sh` calls it
- output binary/script is staged in `dist/<module-id>/bin/`

**Step 2: Run test to verify fail**

Run: `bash tests/test_rtsp_backend_scaffold.sh`
Expected: FAIL initially.

**Step 3: Implement minimal backend build integration**

- Add `scripts/build_rtsp_backend.sh` with deterministic version/tool checks.
- Call it from `scripts/build.sh` in the same orchestration style as current `build_librespot.sh`.
- Keep Docker deps additive, not structural rewrites.

**Step 4: Re-run scaffold test**

Run: `bash tests/test_rtsp_backend_scaffold.sh`
Expected: PASS.

**Step 5: Commit**

```bash
git add scripts/build_rtsp_backend.sh scripts/build.sh scripts/Dockerfile tests/test_rtsp_backend_scaffold.sh
git commit -m "build: stage rtsp backend with existing build contract"
```

### Task 5: Replace Spotify supervisor with RTSP session supervisor in DSP plugin

**Files:**
- Modify: `src/dsp/streamrtsp_plugin.c` (or rename to `src/dsp/screenstream_plugin.c` and update build script)
- Modify: `src/runtime/` helper scripts as needed

**Step 1: Add failing runtime scaffold test**

Create/extend test assertions to ensure:
- no `librespot`-specific process startup in plugin
- RTSP session states are exposed (`scanning`, `connecting`, `buffering`, `streaming`, `reconnecting`, `error`)
- lifecycle params exist (`connect`, `distreamrtsp`, `scan`, `auto_reconnect`)

**Step 2: Run test to verify fail**

Run: `bash tests/test_rtsp_runtime_scaffold.sh`
Expected: FAIL.

**Step 3: Implement minimal supervisor swap**

- Keep ring buffer + underrun smoothing + callback-safe render behavior.
- Replace subprocess launch command with RTSP backend wrapper invocation.
- Preserve robust stop/restart/cleanup behavior and stale-process prevention.

**Step 4: Re-run runtime scaffold test**

Run: `bash tests/test_rtsp_runtime_scaffold.sh`
Expected: PASS.

**Step 5: Commit**

```bash
git add src/dsp/streamrtsp_plugin.c tests/test_rtsp_runtime_scaffold.sh
git commit -m "feat: replace spotify supervisor with rtsp session supervisor"
```

### Task 6: Implement discovery tiers (mDNS -> last-known -> bounded subnet scan)

**Files:**
- Create: `src/runtime/screenstream_discovery.sh`
- Create: `src/runtime/screenstream_scan.sh`
- Modify: `src/dsp/streamrtsp_plugin.c`

**Step 1: Add failing discovery behavior test**

Create `tests/test_rtsp_discovery_scaffold.sh` to assert:
- discovery scripts exist/executable
- DSP plugin consumes discovery result file/state
- fallback scan is bounded/rate-limited

**Step 2: Run failing test**

Run: `bash tests/test_rtsp_discovery_scaffold.sh`
Expected: FAIL.

**Step 3: Implement tiered discovery**

- Tier 1: mDNS/zeroconf browse (when available).
- Tier 2: reconnect via persisted sender identity (not raw IP only).
- Tier 3: bounded subnet RTSP probe fallback.
- Store candidates in a cache file consumed by DSP/UI.

**Step 4: Re-run discovery test**

Run: `bash tests/test_rtsp_discovery_scaffold.sh`
Expected: PASS.

**Step 5: Commit**

```bash
git add src/runtime/screenstream_discovery.sh src/runtime/screenstream_scan.sh src/dsp/streamrtsp_plugin.c tests/test_rtsp_discovery_scaffold.sh
git commit -m "feat: add tiered local discovery and reconnect identity flow"
```

### Task 7: Implement quality-first audio controls and persistence

**Files:**
- Modify: `src/dsp/streamrtsp_plugin.c`
- Modify: `src/module.json`
- Modify: `src/ui.js`

**Step 1: Add failing behavior tests**

Create tests to assert presence/wiring for:
- `gain`
- `mono_sum`
- `buffer_mode` (`normal`, `safe`, `max_stability`)
- headroom/trim setting
- persisted auto-reconnect and last-sender fields

**Step 2: Run tests to verify fail**

Run: `bash tests/test_rtsp_audio_settings.sh`
Expected: FAIL.

**Step 3: Implement minimal behavior**

- Persist required settings under module cache path.
- Keep stereo default; mono sum optional.
- Favor larger stable buffering (latency-secondary policy).

**Step 4: Re-run tests**

Run: `bash tests/test_rtsp_audio_settings.sh`
Expected: PASS.

**Step 5: Commit**

```bash
git add src/dsp/streamrtsp_plugin.c src/module.json src/ui.js tests/test_rtsp_audio_settings.sh
git commit -m "feat: add quality-first audio settings and persistence"
```

### Task 8: Finalize UX flow and advanced fallback UI

**Files:**
- Modify: `src/ui.js`
- Modify: `src/help.json`
- Modify: `README.md`

**Step 1: Add failing UI scaffold checks**

Create `tests/test_rtsp_ui_contract.sh` for:
- scan/list/connect/distreamrtsp actions
- auto reconnect toggle
- status labels and stream info display (`codec`, `sample_rate`, `channels`, `buffer_health`, `last_error`)
- hidden/advanced manual URL fallback

**Step 2: Run test to verify fail**

Run: `bash tests/test_rtsp_ui_contract.sh`
Expected: FAIL.

**Step 3: Implement UI/menu updates**

- Keep menu helper architecture and input handling pattern.
- Ensure manual endpoint entry is clearly non-primary.
- Surface concise status and last error text; hide noisy internals.

**Step 4: Re-run UI test**

Run: `bash tests/test_rtsp_ui_contract.sh`
Expected: PASS.

**Step 5: Commit**

```bash
git add src/ui.js src/help.json README.md tests/test_rtsp_ui_contract.sh
git commit -m "feat: deliver rtsp user flow with discovery-first ui and fallback controls"
```

### Task 9: Implement resampling and clock-drift control

**Files:**
- Modify: `src/dsp/streamrtsp_plugin.c`
- Modify: `src/runtime/` backend wrapper scripts as needed
- Create: `tests/test_rtsp_resampler_drift.sh`

**Step 1: Add failing resampler/drift test**

Create `tests/test_rtsp_resampler_drift.sh` to assert:
- one final output-rate conversion stage is defined
- no multi-hop sample-rate conversion chain is used
- drift policy exists (buffer target + correction strategy) and is not hard reset only

**Step 2: Run failing test**

Run: `bash tests/test_rtsp_resampler_drift.sh`
Expected: FAIL before implementation.

**Step 3: Implement quality-first drift handling**

- Add high-quality final resampling path when source rate differs from Move output.
- Add conservative drift correction that prevents long-run buffer creep/oscillation.
- Preserve stereo default and avoid extra transcoding stages.

**Step 4: Re-run resampler/drift test**

Run: `bash tests/test_rtsp_resampler_drift.sh`
Expected: PASS.

**Step 5: Commit**

```bash
git add src/dsp/streamrtsp_plugin.c src/runtime tests/test_rtsp_resampler_drift.sh
git commit -m "feat: add quality resampling and drift compensation for long sessions"
```

### Task 10: Security hardening for endpoint and process launch

**Files:**
- Modify: `src/dsp/streamrtsp_plugin.c`
- Modify: `src/runtime/screenstream_backend.sh` (or equivalent launcher)
- Create: `tests/test_rtsp_security_guards.sh`

**Step 1: Add failing security test**

Create `tests/test_rtsp_security_guards.sh` to assert:
- endpoint validation/sanitization path exists
- backend invocation avoids unsafe shell interpolation patterns
- manual endpoint fallback is constrained to local-network RTSP use

**Step 2: Run failing test**

Run: `bash tests/test_rtsp_security_guards.sh`
Expected: FAIL.

**Step 3: Implement hardening**

- Validate protocol, host, port, and path bounds before connect.
- Use safe argument passing in helper launch paths.
- Reject suspicious/unsupported endpoint forms with clear errors.

**Step 4: Re-run security test**

Run: `bash tests/test_rtsp_security_guards.sh`
Expected: PASS.

**Step 5: Commit**

```bash
git add src/dsp/streamrtsp_plugin.c src/runtime tests/test_rtsp_security_guards.sh
git commit -m "feat: harden rtsp endpoint validation and backend launch safety"
```

### Task 11: Complete edge-case error matrix handling

**Files:**
- Modify: `src/dsp/streamrtsp_plugin.c`
- Modify: `src/runtime/` parser/supervisor scripts
- Create: `tests/test_rtsp_error_matrix.sh`

**Step 1: Add failing error matrix test**

Create `tests/test_rtsp_error_matrix.sh` with checks for explicit handling of:
- auth requested
- unsupported codec
- stream with no audio
- stream with video only
- endpoint timeout/unreachable sender

**Step 2: Run failing test**

Run: `bash tests/test_rtsp_error_matrix.sh`
Expected: FAIL.

**Step 3: Implement robust handling**

- Map backend failure signatures to user-safe status/errors.
- Ensure each path returns to a sane reconnectable state.
- Ensure distreamrtsp/unload from any error state leaves no zombie subprocess.

**Step 4: Re-run error matrix test**

Run: `bash tests/test_rtsp_error_matrix.sh`
Expected: PASS.

**Step 5: Commit**

```bash
git add src/dsp/streamrtsp_plugin.c src/runtime tests/test_rtsp_error_matrix.sh
git commit -m "feat: add explicit error handling for rtsp edge cases"
```

### Task 12: Expand status/diagnostics surfaces required by v1

**Files:**
- Modify: `src/dsp/streamrtsp_plugin.c`
- Modify: `src/ui.js`
- Modify: `src/help.json`
- Create: `tests/test_rtsp_status_fields.sh`

**Step 1: Add failing status field test**

Create `tests/test_rtsp_status_fields.sh` to assert required read-only fields are exposed and displayed:
- `codec`
- `sample_rate`
- `channels`
- `buffer_health`
- `last_error`
- selected device identity

**Step 2: Run failing test**

Run: `bash tests/test_rtsp_status_fields.sh`
Expected: FAIL.

**Step 3: Implement status/diagnostics wiring**

- Add DSP `get_param` keys for stream-format/buffer/error status.
- Render concise values in UI without noisy internal logs.
- Keep help text aligned with displayed fields.

**Step 4: Re-run status field test**

Run: `bash tests/test_rtsp_status_fields.sh`
Expected: PASS.

**Step 5: Commit**

```bash
git add src/dsp/streamrtsp_plugin.c src/ui.js src/help.json tests/test_rtsp_status_fields.sh
git commit -m "feat: expose required stream status and diagnostics fields"
```

### Task 13: Long-session soak + lifecycle shutdown gate

**Files:**
- Create: `tests/test_rtsp_soak_gate.sh`
- Modify: `README.md`
- Modify: `docs/DEV_NOTES.md` (create if absent)

**Step 1: Add failing soak/lifecycle gate**

Create `tests/test_rtsp_soak_gate.sh` to define and enforce:
- minimum long-session playback soak checklist
- reconnect-after-drop checklist
- unload cleanup checklist confirming no leftover helper processes

**Step 2: Run failing gate**

Run: `bash tests/test_rtsp_soak_gate.sh`
Expected: FAIL until checklist/doc contract exists.

**Step 3: Implement and document soak gate**

- Add reproducible soak procedure with expected pass criteria.
- Add explicit orphan-process verification commands.
- Document required pre-release pass evidence in README/dev notes.

**Step 4: Re-run soak gate**

Run: `bash tests/test_rtsp_soak_gate.sh`
Expected: PASS.

**Step 5: Commit**

```bash
git add tests/test_rtsp_soak_gate.sh README.md docs/DEV_NOTES.md
git commit -m "test: add long-session soak and lifecycle cleanup release gate"
```

### Task 14: Requirements traceability gate

**Files:**
- Create: `docs/REQUIREMENTS_TRACEABILITY.md`
- Create: `tests/test_requirements_traceability.sh`

**Step 1: Add failing traceability test**

Create `tests/test_requirements_traceability.sh` that requires each major requirement group to map to at least one task/test artifact.

**Step 2: Run failing traceability test**

Run: `bash tests/test_requirements_traceability.sh`
Expected: FAIL before traceability doc exists.

**Step 3: Implement traceability matrix**

- Add `docs/REQUIREMENTS_TRACEABILITY.md` with requirement-to-task/test mapping.
- Include acceptance criteria, non-goals enforcement, lifecycle and security gates.

**Step 4: Re-run traceability test**

Run: `bash tests/test_requirements_traceability.sh`
Expected: PASS.

**Step 5: Commit**

```bash
git add docs/REQUIREMENTS_TRACEABILITY.md tests/test_requirements_traceability.sh
git commit -m "docs: add requirements traceability matrix and gate"
```

### Task 15: End-to-end verification and release readiness gate

**Files:**
- Modify as needed: docs/tests/scripts for fixes uncovered by verification

**Step 1: Run full test suite**

Run:
- `bash tests/test_release_metadata.sh`
- `bash tests/test_rtsp_scaffold_identity.sh`
- `bash tests/test_rtsp_backend_scaffold.sh`
- `bash tests/test_rtsp_runtime_scaffold.sh`
- `bash tests/test_rtsp_discovery_scaffold.sh`
- `bash tests/test_rtsp_audio_settings.sh`
- `bash tests/test_rtsp_ui_contract.sh`
- `bash tests/test_rtsp_resampler_drift.sh`
- `bash tests/test_rtsp_security_guards.sh`
- `bash tests/test_rtsp_error_matrix.sh`
- `bash tests/test_rtsp_status_fields.sh`
- `bash tests/test_rtsp_soak_gate.sh`
- `bash tests/test_requirements_traceability.sh`

Expected: all PASS.

**Step 2: Verify no stale Spotify/librespot references remain unintentionally**

Run: `rg -n "spotify|librespot|streamrtsp" README.md src scripts tests release.json .github/workflows || true`
Expected: only intentional compatibility notes and migration references.

**Step 3: Verify packaging outputs**

Run: `./scripts/build.sh`
Expected:
- module folder staged in `dist/<module-id>/`
- release artifact `dist/<rtsp-artifact>.tar.gz`

**Step 4: Commit verification fixes**

```bash
git add -A
git commit -m "chore: finalize rtsp module verification and release readiness"
```

## Requirements Coverage Map

- Product/transport/local-only/no-manual-mainflow: Tasks 3, 5, 6, 8.
- Discovery tiers + reconnect identity: Task 6.
- Audio-only decode + quality-first buffering: Tasks 5, 7, 9.
- Drift/resample long-session stability: Task 9, Task 13.
- Security/safety expectations: Task 10.
- Error handling matrix and sane recovery: Task 11.
- Required UI/status fields and persistence: Tasks 7, 8, 12.
- Clean lifecycle/no orphan helpers: Tasks 5, 11, 13.
- Build/release/update-not-rewrite workflow contract: Tasks 1, 2, 4, 15.
- Acceptance criteria closure + explicit traceability: Tasks 14, 15.

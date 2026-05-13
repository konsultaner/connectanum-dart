# Exec Plan: autonomy-hardening

Status: completed
Owner: Codex
Created: 2026-04-21
Last updated: 2026-04-21

## Goal

Make the root repo workflow runnable from Codex's plain non-login shell on macOS without manual PATH fixes, and make verification deterministic by skipping Linux-only native slices on unsupported hosts while preserving browser coverage.

## Scope

- In scope: root bootstrap/test script hardening, non-Linux test gating, browser verification fixes, unsupported-host build-hook behavior, and startup-state documentation.
- Out of scope: CI workflow alignment, roadmap reshaping, and package README cleanup.

## Files Expected To Change

- `bin/common.sh`
- `bin/test-fast`
- `bin/test-all`
- `packages/connectanum_bench/test/wamp_transport_integration_test.dart`
- `packages/connectanum_client/dart_test.yaml`
- `packages/connectanum_client/hook/build.dart`
- `packages/connectanum_client/test/transport/websocket/websocket_transport_web_test.dart`
- `packages/connectanum_router/hook/build.dart`
- `docs/project_state.md`

## Preconditions

- Flutter SDK available locally so `dart` can be discovered.
- Rust stable toolchain available locally.
- Chrome or Chromium installed locally for browser tests.
- Native runtime support remains Linux-only.

## Plan

1. Harden root shell discovery for Dart, Rust, Chrome, and native library paths.
2. Split fast/full verification so non-Linux hosts skip Linux-only runtime slices but still exercise portable Dart coverage.
3. Fix browser verification to run from the client package context, close cleanly, and stop unsupported-host build hooks from failing pure Dart/browser flows.
4. Re-run root verification and refresh the checked-in project state.

## Verification

- `bin/test-fast`
- `bin/verify`
- Additional targeted commands:
  - `dart test packages/connectanum_client/test/transport/websocket/websocket_transport_web_test.dart -p chrome --timeout=30s --concurrency=1 -r expanded` from the workspace root to reproduce the broken browser asset path
  - `PATH="$HOME/Applications/Chromium.app/Contents/MacOS:$PATH" dart test test/transport/websocket/websocket_transport_web_test.dart -p chrome --timeout=60s --concurrency=1 -r expanded` from `packages/connectanum_client` to validate the fixed browser path

## Decision Log

- 2026-04-21: Chose to skip Linux-only native runtime suites on non-Linux hosts instead of forcing unsupported failures in the root scripts.
- 2026-04-21: Switched browser verification to run from `packages/connectanum_client` so package-specific `dart_test.yaml` and browser asset serving resolve correctly.
- 2026-04-21: Made client/router build hooks no-op on unsupported hosts so pure Dart/browser workflows continue on macOS without pretending the native runtime itself is supported there.

## Handoff

- `bin/bootstrap`, `bin/test-fast`, and `bin/verify` now pass from the plain non-login shell used by Codex on this macOS machine.
- Non-Linux verification intentionally skips Linux-only native runtime slices and still exercises the portable Dart suites plus the browser websocket test.
- Remaining follow-up work is non-blocking: align CI with the root `bin/*` entrypoints and refresh stale package-level docs.

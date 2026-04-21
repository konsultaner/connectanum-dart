# Exec Plan: macos-native-runtime

Status: completed
Owner: Codex
Created: 2026-04-21
Last updated: 2026-04-21

## Goal

Make the `ct_ffi` native transport runtime usable on this macOS machine and bring the root verification flow along with it so local work can exercise native coverage without switching to Linux.

## Scope

- In scope: native platform gating, macOS host build-hook support, native library discovery, macOS-safe router verification coverage, and startup-state documentation.
- Out of scope: fixing the router remote-auth TLS integration failure on macOS, CI workflow alignment, and broader package README cleanup.

## Files Expected To Change

- `native/transport/ct_core/src/platform/mod.rs`
- `native/transport/ct_core/src/platform/linux.rs`
- `native/transport/ct_ffi/src/tests/mod.rs`
- `packages/connectanum_client/hook/build.dart`
- `packages/connectanum_client/lib/src/transport/native/runtime.dart`
- `packages/connectanum_router/hook/build.dart`
- `packages/connectanum_router/test/native/native_runtime_test.dart`
- `packages/connectanum_router/test/support/native_lib.dart`
- `bin/common.sh`
- `bin/test-fast`
- `bin/test-all`
- `docs/project_state.md`

## Preconditions

- Flutter-bundled Dart, Rust stable, and Chrome/Chromium are available locally on macOS.
- The native router runtime still exposes process-global state, so package-wide parallel execution is unsafe for some native integration tests on macOS.

## Plan

1. Remove the Linux-only gating that was forcing the macOS build onto the unsupported platform path, and enable macOS host builds plus native library lookup for `.dylib`.
2. Reproduce macOS-native router test behavior, then shape the root verification scripts around a macOS-safe sequential subset instead of the Linux package-wide parallel sweep.
3. Re-run targeted native verification plus the root `bin/test-fast` and `bin/verify` entrypoints, then refresh the checked-in project state.

## Verification

- `cargo test --manifest-path native/transport/Cargo.toml -p ct_core`
- `cargo test --manifest-path native/transport/Cargo.toml -p ct_ffi`
- `dart test packages/connectanum_client/test/transport/native/native_transports_test.dart`
- `dart test packages/connectanum_router/test/native/ffi_test_mode_test.dart --concurrency=1`
- `dart test packages/connectanum_router/test/native/native_runtime_test.dart --concurrency=1`
- `dart test packages/connectanum_router/test/router_integration_native_test.dart --concurrency=1`
- `dart test packages/connectanum_router/test/router_integration_websocket_test.dart --concurrency=1`
- `bin/test-fast`
- `bin/verify`
- Additional targeted commands:
  - `dart test packages/connectanum_router/test --concurrency=12` to reproduce the macOS isolate/runtime collision
  - `dart test packages/connectanum_router/test/remote_auth_integration_test.dart --concurrency=1` to confirm the remaining macOS TLS follow-up

## Decision Log

- 2026-04-21: Enabled the shared Unix runtime implementation on macOS because the Rust transport code already compiled and passed targeted tests there; the earlier Linux-only split was a repo policy gate, not a hard platform implementation boundary.
- 2026-04-21: Kept the macOS router native verification in explicit sequential slices because full-package parallel execution crashes with process-global runtime and native-callback isolate conflicts.
- 2026-04-21: Left `remote_auth_integration_test.dart` out of the macOS root verification flow because it still fails with TLS certificate verification and timeout behavior on this host.

## Handoff

- The native transport library now builds and runs on this macOS machine, including Dart client native transport tests and the macOS-safe router native integration slices.
- `bin/test-fast` and `bin/verify` both pass from Codex's plain non-login shell on Darwin arm64.
- Remaining follow-up work is narrow: investigate the remote-auth TLS integration failure on macOS and, separately, align CI/docs with the canonical root workflow.

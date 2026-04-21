# Project State

Last updated: 2026-04-21
Current branch: `add-router`
Last reviewed commit: `28830f2` (`test(ct_core): stabilize runtime tests`)

## Resume Order

1. Read `AGENTS.md`.
2. Read this file.
3. If there is an active plan under `docs/exec-plans/`, read that plan next.
4. Use `ROADMAP_NEXT.md` only to choose the next milestone after checking active plans.
5. Use `ROADMAP.md` and `STRUCTURE.md` as reference material when details are needed.

## Current Operational Truth

- The repo is a Dart workspace plus a Rust native transport workspace.
- The canonical root entrypoints are `bin/bootstrap`, `bin/test-fast`, `bin/test-all`, and `bin/verify`.
- Root shell helpers now auto-detect Dart from Flutter, Rust from `~/.cargo`, Chrome/Chromium, and the standard prebuilt native library path.
- GitHub Actions CI is being aligned with the canonical root `bin/*` entrypoints under `docs/exec-plans/2026-04-21-ci-alignment.md`.
- The CI workflow now targets all branch pushes plus PRs to `master`, and it also exposes `workflow_dispatch` for manual runs.
- The root router verification now runs from `packages/connectanum_router` so the package-local `dart_test.yaml` (`concurrency: 1`) applies to the full suite on every host.
- The bench WAMP integration tests now resolve their worker helper from either the bench package root or the repo root so Linux CI and local root-script runs share the same path contract.
- The `ct_core` runtime test suite now keeps the rawsocket config connection alive through its assertions and recovers the shared test mutex after prior panics so Linux `cargo test -p ct_core` does not cascade `PoisonError` failures after one flaky test.
- Native runtime execution is now validated on both Linux and macOS; unsupported hosts still skip the native runtime slices.
- Root verification now covers the full router package, including `publish_ack_test.dart` and `remote_auth_integration_test.dart`, while still serialising native runtime work through the router package's checked-in test config.
- Package-local browser verification now runs from `packages/connectanum_client`, and the client/router build hooks build on Linux and macOS while still no-oping on unsupported hosts.
- The local autonomy blockers from the 2026-04-21 audit are resolved for this macOS shell environment.
- Codex heartbeat automations run in a stricter sandbox than the normal interactive shell here; they can reuse the local pub cache with a temporary writable `HOME`, but loopback socket binds are blocked, so socket-heavy local verification must still be confirmed in CI or an unrestricted thread.
- This heartbeat sandbox currently cannot reach GitHub, so remote CI status must still be confirmed from an unrestricted shell, a network-capable Codex run, or GitHub itself.

## Environment Requirements

- Dart SDK `^3.9.2` (Flutter-bundled Dart is acceptable)
- Rust stable toolchain
- A Chrome or Chromium executable for browser-platform tests
- `CONNECTANUM_NATIVE_LIB` pointing at a prebuilt `ct_ffi` library when the standard release path is not used
- Linux or macOS is required for native runtime execution tests; other hosts verify the portable suites and browser coverage instead

## Verification Status

- 2026-04-21: `bin/bootstrap` passed in a plain non-login shell on Darwin arm64.
- 2026-04-21: `bin/test-fast` passed in a plain non-login shell on Darwin arm64, including the native client transport fast tests and the sequential router native runtime smoke test.
- 2026-04-21: `bin/verify` passed in a plain non-login shell on Darwin arm64, including `ct_core`/`ct_ffi` Rust tests, the `ffi-test` native release build, native client transport tests, the full router package from `packages/connectanum_router`, and the Chromium/Dart2Wasm browser websocket test from `packages/connectanum_client`.
- 2026-04-21: `cd packages/connectanum_router && dart test test` passed on Darwin arm64, including `publish_ack_test.dart`, `remote_auth_integration_test.dart`, `router_integration_native_test.dart`, and `router_integration_websocket_test.dart` under the router package's checked-in serial test configuration.
- 2026-04-21: `bin/verify` passed again on Darwin arm64 after updating `bin/test-all` to run the router suite from `packages/connectanum_router`, so the root verification flow now exercises the full router package with the same package-local concurrency contract that GitHub CI needs.
- 2026-04-21: `dart test packages/connectanum_router/test/remote_auth_integration_test.dart --concurrency=1 -r expanded` passed on Darwin arm64 after rotating the remote-auth TLS fixtures to an Apple-compatible server certificate lifetime.
- 2026-04-21: `cargo test --manifest-path native/transport/Cargo.toml -p ct_core connection_runtime_config_exposes_rawsocket_settings -- --nocapture` passed on Darwin arm64 after keeping the test connection alive through runtime-config assertions.
- 2026-04-21: `cargo test --manifest-path native/transport/Cargo.toml -p ct_core runtime_starts_only_once -- --nocapture` passed on Darwin arm64 after making the shared Rust test guard recover from poisoned mutex state.
- 2026-04-21: GitHub Actions run `24730190112` reached green `Fast Checks`, then failed in `Full Verify` because `bin/test-all` invoked `dart test packages/connectanum_router/test` from the repo root, which bypassed `packages/connectanum_router/dart_test.yaml` and let `remote_auth_integration_test.dart` collide with the process-global native runtime in Linux CI.

## Active Plan

- Active execution plan: `docs/exec-plans/2026-04-21-ci-alignment.md`
- Most recent completed plan before this: `docs/exec-plans/2026-04-21-macos-remote-auth-tls.md`
- Use `docs/exec-plans/template.md` for the next substantial cross-package/native task only when this active plan is complete.

## Known Follow-Ups

- Refresh stale package-level docs so they match the monorepo and root-script workflow.

## Update Checklist

- Refresh this file when the active milestone, blockers, or last-known verification status changes.
- Record the exact commands that most recently passed.
- Link the active execution plan and any follow-up docs created during external research.

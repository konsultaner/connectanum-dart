# Project State

Last updated: 2026-04-21
Current branch: `add-router`
Last reviewed commit: `d6b9c46` (`feat(auth): secure remote auth and pin WAMP conformance vectors`)

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
- Native runtime execution is now validated on both Linux and macOS; unsupported hosts still skip the native runtime slices.
- On macOS, the root router verification uses explicit sequential native slices instead of the Linux package-wide sweep because the native runtime and callback bridge are process-global and unsafe under parallel package execution.
- Package-local browser verification now runs from `packages/connectanum_client`, and the client/router build hooks build on Linux and macOS while still no-oping on unsupported hosts.
- The local autonomy blockers from the 2026-04-21 audit are resolved for this macOS shell environment.
- Codex heartbeat automations run in a stricter sandbox than the normal interactive shell here; they can reuse the local pub cache with a temporary writable `HOME`, but loopback socket binds are blocked, so socket-heavy local verification must still be confirmed in CI or an unrestricted thread.

## Environment Requirements

- Dart SDK `^3.9.2` (Flutter-bundled Dart is acceptable)
- Rust stable toolchain
- A Chrome or Chromium executable for browser-platform tests
- `CONNECTANUM_NATIVE_LIB` pointing at a prebuilt `ct_ffi` library when the standard release path is not used
- Linux or macOS is required for native runtime execution tests; other hosts verify the portable suites and browser coverage instead

## Verification Status

- 2026-04-21: `bin/bootstrap` passed in a plain non-login shell on Darwin arm64.
- 2026-04-21: `bin/test-fast` passed in a plain non-login shell on Darwin arm64, including the native client transport fast tests and the sequential router native runtime smoke test.
- 2026-04-21: `bin/verify` passed in a plain non-login shell on Darwin arm64, including `ct_core`/`ct_ffi` Rust tests, the `ffi-test` native release build, native client transport tests, the macOS-safe sequential router native slices, and the Chromium/Dart2Wasm browser websocket test from `packages/connectanum_client`.
- 2026-04-21: `dart test packages/connectanum_router/test/remote_auth_integration_test.dart --concurrency=1 -r expanded` passed on Darwin arm64 after rotating the remote-auth TLS fixtures to an Apple-compatible server certificate lifetime.

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

# Project State

Last updated: 2026-04-22
Current branch: `add-router`
Last reviewed commit: `fd01216` (`feat(e2ee): add wamp secretbox provider`)

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
- GitHub Actions CI now runs through the canonical root `bin/*` entrypoints on branch pushes and PRs to `master`; GitHub Actions run `24732889424` for `2fac53b` completed successfully with both `Fast Checks` and `Full Verify`.
- The CI workflow now targets all branch pushes plus PRs to `master`, and it also exposes `workflow_dispatch` for manual runs.
- The root router verification now runs from `packages/connectanum_router` so the package-local `dart_test.yaml` (`concurrency: 1`) applies to the full suite on every host.
- The bench WAMP integration tests now resolve their worker helper from either the bench package root or the repo root so Linux CI and local root-script runs share the same path contract.
- The bench now ships `native/bench/scenarios/transport_mbit_matrix_throughput.toml` as the throughput-grade counterpart to the cross-transport/auth/authz smoke matrix, preserving the same auth/authz/public/protected row shape while raising sustained-workload settings for one canonical Mbps artifact set.
- `connectanum_core` now exposes a typed `WampE2eeProvider` contract plus an explicit `WampE2eeProviderUnavailableException`, so `ppt_scheme = "wamp"` payloads no longer silently materialize empty args/kwargs when no decryptor is available.
- The Dart client/session path now threads an optional `e2eeProvider` through outbound publish/call/yield packing, materialized inbound messages, and native direct-result/event/invocation payload views while preserving the existing packed-byte passthrough behavior for matching lazy WAMP payloads.
- The first Dart-side WAMP E2EE prototype is now implemented. `connectanum_core` ships `WampCborXsalsa20Poly1305Provider`, explicit unsupported-cipher / missing-key / invalid-payload / decryption failure types, and a focused provider regression test.
- Client and router coverage now prove the full phase-1 path: outbound WAMP payloads populate `ppt_cipher` + `ppt_keyid`, inbound native direct result/event/invocation paths decrypt through the configured provider, and router internal-session forwarding preserves ciphertext bytes plus `ppt_*` metadata without forcing router-side decryption.
- The `ct_core` runtime test suite now keeps the rawsocket config connection alive through its assertions and recovers the shared test mutex after prior panics so Linux `cargo test -p ct_core` does not cascade `PoisonError` failures after one flaky test.
- The `ct_ffi` `runtime::ffi` unit tests now use the same shared suite guard as the rest of the FFI tests before touching global message handles, so concurrent `ct_shutdown()` calls from other tests no longer invalidate those handles mid-assertion.
- The native Rust workspace no longer emits the previously-tracked dead-code warning block during local verification; the cleanup landed in `2fac53b` without changing runtime behavior.
- The `ct_ffi` HTTP/3 idle-timeout regression test now asserts directly on the emitted HTTP/3 connection event instead of waiting on a separate accepted-connection callback, which removes a full-suite race that could intermittently fail `bin/verify`.
- Native runtime execution is now validated on both Linux and macOS; unsupported hosts still skip the native runtime slices.
- Root verification now covers the full router package, including `publish_ack_test.dart` and `remote_auth_integration_test.dart`, while still serialising native runtime work through the router package's checked-in test config.
- Package-local browser verification now runs from `packages/connectanum_client`, and the client/router build hooks build on Linux and macOS while still no-oping on unsupported hosts.
- The client/router build hooks now reuse `CONNECTANUM_NATIVE_LIB` for prebuilt binaries and honor `CONNECTANUM_SKIP_NATIVE_BUILD=1` for deployments that intentionally provide `ct_ffi` themselves, instead of invoking Cargo unconditionally.
- The client native runtime loader now falls back to the bare platform library name after hooks/local-build probing, so system-installed `ct_ffi` behaves the same way on the client path as it already did on the router path.
- The local autonomy blockers from the 2026-04-21 audit are resolved for this macOS shell environment.
- In-app heartbeat sandboxes are more restricted than the interactive shell here; remote CI inspection and git metadata writes should still happen from unrestricted interactive runs or the external launchd worker.

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
- 2026-04-21: `cargo test --manifest-path native/transport/Cargo.toml -p ct_core`, `cargo test --manifest-path native/transport/Cargo.toml -p ct_ffi`, and `bin/verify` all passed on Darwin arm64 after `2fac53b` removed the known Rust dead-code warning block from local verification output.
- 2026-04-21: GitHub Actions run `24732889424` passed on `add-router` for commit `2fac53b`, with both `Fast Checks` and `Full Verify` green.
- 2026-04-21: `bin/test-fast` passed again on Darwin arm64 before the transport/auth/authz throughput-matrix update.
- 2026-04-21: `python3` `tomllib` parsing confirmed `native/bench/scenarios/transport_mbit_matrix_throughput.toml` loads cleanly with 57 uniquely named workloads.
- 2026-04-21: `cargo test --manifest-path native/transport/Cargo.toml -p ct_ffi http3_idle_timeout_emits_connection_event -- --nocapture` passed three consecutive reruns on Darwin arm64 after removing the flaky accepted-connection dependency from the test.
- 2026-04-21: `bin/verify` passed on Darwin arm64 after adding `native/bench/scenarios/transport_mbit_matrix_throughput.toml` and stabilizing `ct_ffi`'s HTTP/3 idle-timeout regression test.
- 2026-04-21: `cargo test --manifest-path native/transport/Cargo.toml -p ct_ffi runtime::ffi::tests -- --nocapture` and `cargo test --manifest-path native/transport/Cargo.toml -p ct_ffi -- --nocapture` passed on Darwin arm64 after putting the `runtime::ffi` unit tests under the shared FFI test guard so parallel `ct_shutdown()` calls can no longer clear their message handles.
- 2026-04-21: `bin/verify` passed again on Darwin arm64 after starting the E2EE/PPT research spike docs and fixing the `ct_ffi` shared-state FFI test race.
- 2026-04-22: `cd packages/connectanum_core && dart test test/message_result_test.dart test/message_invocation_test.dart -r expanded` passed on Darwin arm64 after landing the `WampE2eeProvider` contract, explicit missing-provider errors, and provider-backed WAMP invocation/result tests.
- 2026-04-22: `cd packages/connectanum_client && dart test test/client_test.dart -p vm -r expanded` passed on Darwin arm64 after threading `Client.e2eeProvider` through the session/native fast path and adding outbound/inbound WAMP provider coverage.
- 2026-04-22: `bin/verify` passed on Darwin arm64 after landing the core/client E2EE provider plumbing and focused tests.
- 2026-04-22: `bin/test-fast` passed on Darwin arm64 before landing the concrete `WampCborXsalsa20Poly1305Provider` implementation and router passthrough assertions.
- 2026-04-22: `dart test packages/connectanum_core/test/message_e2ee_payload_test.dart packages/connectanum_core/test/message_result_test.dart packages/connectanum_core/test/message_invocation_test.dart -r expanded` passed on Darwin arm64 after replacing the provider test doubles with the real `xsalsa20poly1305` implementation and adding explicit key/cipher/decrypt failure coverage.
- 2026-04-22: `dart test packages/connectanum_client/test/client_test.dart -r expanded` passed on Darwin arm64 after asserting provider-backed `ppt_cipher` / `ppt_keyid` propagation and native direct-result decrypts against the real implementation.
- 2026-04-22: `dart test packages/connectanum_router/test/router_runtime_test.dart -r expanded` passed on Darwin arm64 after pinning `ppt_cipher` / `ppt_keyid` passthrough on internal-session WAMP lazy publish/call flows.
- 2026-04-22: `bin/verify` passed on Darwin arm64 after landing the concrete `WampCborXsalsa20Poly1305Provider`, the new provider regression file, and the router/client metadata assertions.
- 2026-04-22: `bin/test-fast` passed on Darwin arm64 before landing the native build-hook packaging updates.
- 2026-04-22: `cd packages/connectanum_router && dart test test/hook/build_hook_test.dart -r expanded` passed on Darwin arm64 after teaching the router build hook to reuse `CONNECTANUM_NATIVE_LIB` and honor `CONNECTANUM_SKIP_NATIVE_BUILD=1`.
- 2026-04-22: `cd packages/connectanum_client && dart test test/hook/build_hook_test.dart -r expanded` passed on Darwin arm64 after teaching the client build hook to reuse `CONNECTANUM_NATIVE_LIB` and honor `CONNECTANUM_SKIP_NATIVE_BUILD=1`.
- 2026-04-22: `cd packages/connectanum_client && dart test test/transport/native/native_library_loader_test.dart -r expanded` passed on Darwin arm64 after making the client runtime loader fall back to the bare platform library name for system-installed `ct_ffi`.
- 2026-04-22: `bin/verify` passed on Darwin arm64 after landing the native build-hook packaging contract, the new hook regressions, the client loader fallback, and the associated doc updates.

## Active Plan

- No active execution plan is checked in right now.
- Supporting research note: `docs/e2ee_ppt_research.md`
- Most recent completed plan: `docs/exec-plans/2026-04-22-native-build-hook-packaging.md`
- Completed immediately before that: `docs/exec-plans/2026-04-21-e2ee-research-spike.md`

## Known Follow-Ups

- CI/release packaging for prebuilt `ct_ffi` artifacts and/or install-time (`dart pub get`) native build hooks still needs a dedicated implementation pass.

## Update Checklist

- Refresh this file when the active milestone, blockers, or last-known verification status changes.
- Record the exact commands that most recently passed.
- Link the active execution plan and any follow-up docs created during external research.

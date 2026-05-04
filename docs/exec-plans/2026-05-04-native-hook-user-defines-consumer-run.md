# Exec Plan: Native Hook User Defines Consumer Run

Status: local verification complete; hosted evidence pending
Owner: Codex
Created: 2026-05-04
Last updated: 2026-05-04

## Goal

Make the client/router native build-hook configuration work in real consumer
`dart run` contexts, where the Dart SDK strips non-allowlisted shell
environment variables from hook processes, and prove the public MCP/client/router
entrypoints can run from a temporary downstream package without invoking Cargo
when a prebuilt native library is configured.

## Scope

In scope:

- Teach the `connectanum_client` and `connectanum_router` build hooks to read
  `CONNECTANUM_NATIVE_LIB`, `CONNECTANUM_NATIVE_RELEASE_TAG`,
  `CONNECTANUM_NATIVE_RELEASE_REPOSITORY`, and
  `CONNECTANUM_SKIP_NATIVE_BUILD` from `hooks.user_defines`.
- Keep the explicit injected-environment fallback for direct hook tests and
  manual hook debugging.
- Upgrade the external MCP consumer package smoke from analyze-only to
  `dart run` with hook user defines.
- Refresh public setup docs so consumer applications use cache-safe hook
  configuration instead of SDK-stripped shell variables.

Out of scope:

- Changing native artifact publishing, release tags, or package ownership.
- Adding private downstream application references.
- Solving true `dart pub get`-time native acquisition before the Dart SDK
  exposes a supported install-time hook model.

## Plan

1. Confirm the SDK hook environment behavior and run the fast pre-change
   baseline.
2. Add user-define backed settings resolution to both package build hooks.
3. Move hook tests for prebuilt, release-download, and skip paths onto
   `PackageUserDefines`.
4. Upgrade the consumer package smoke to run the temporary package with hook
   user defines and no private imports.
5. Run focused hook tests, the consumer smoke, `bin/test-fast`, and
   `bin/verify`.
6. Push and collect hosted CI/deployment-chain evidence.

## Verification

- Pre-change `bin/test-fast` passed on 2026-05-04.
- Focused hook tests passed on 2026-05-04:
  `dart test packages/connectanum_client/test/hook/build_hook_test.dart -r expanded`
  and
  `dart test packages/connectanum_router/test/hook/build_hook_test.dart -r expanded`.
- Focused consumer package smoke passed on 2026-05-04:
  `bash -lc 'source bin/common.sh && cd_repo_root && run_mcp_consumer_package_smoke'`.
- Post-change `bin/test-fast` passed on 2026-05-04 and included the upgraded
  temporary consumer package smoke with a real `dart run`.
- Full local `bin/verify` passed on 2026-05-04. It included formatting, Rust
  native/FFI tests, Python package-artifact checks, MCP package tests, client
  tests, auth-server tests, bench integration tests, router-hosted MCP example
  smoke, the upgraded consumer package smoke, full router package tests
  including router-hosted MCP auth/session coverage and hook user-define tests,
  zero-copy router checks, and Chrome Dart2Wasm WebSocket transport tests.

## Handoff

Implementation and local verification are complete. Hosted GitHub evidence is
pending after push.

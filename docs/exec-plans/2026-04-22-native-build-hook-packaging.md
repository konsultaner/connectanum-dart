# Exec Plan: native-build-hook-packaging

Status: completed
Owner: Codex
Created: 2026-04-22
Last updated: 2026-04-22

## Goal

Let `connectanum_router` and `connectanum_client` run with prebuilt or
system-installed `ct_ffi` libraries without always rebuilding the Rust
workspace from their Dart native-asset build hooks.

## Scope

- In scope:
  - Hook support for reusing a prebuilt library via
    `CONNECTANUM_NATIVE_LIB`.
  - Hook opt-out support for deployments that intentionally provide a system or
    externally managed shared library.
  - Align client runtime loading with the router's system-library fallback.
  - Update the checked-in docs and roadmap state to reflect the new packaging
    contract.
- Out of scope:
  - CI artifact publishing or release packaging for prebuilt binaries.
  - `dart pub get` / install-time build hooks.
  - Windows-native runtime validation.

## Files Expected To Change

- `packages/connectanum_router/hook/build.dart`
- `packages/connectanum_client/hook/build.dart`
- `packages/connectanum_client/lib/src/transport/native/runtime.dart`
- `packages/connectanum_router/test/...`
- `packages/connectanum_client/test/...`
- `README.md`
- `packages/connectanum_client/README.md`
- `docs/deployment.md`
- `docs/project_state.md`
- `ROADMAP.md`
- `ROADMAP_NEXT.md`

## Preconditions

- Dart and Rust toolchains remain available for the default build-hook path.
- Tests that exercise the hook contract can run from package-local directories
  so the hook test harness reads the correct `pubspec.yaml`.

## Plan

1. Add build-hook override handling for `CONNECTANUM_NATIVE_LIB` and an
   explicit skip knob for deployments that do not want Cargo invoked.
2. Add focused regression coverage for both hook modes and make the client
   runtime fall back to the bare library name like the router runtime already
   does.
3. Refresh roadmap/project-state docs, then run `bin/verify`.

## Verification

- `bin/test-fast`
- `bin/verify`
- Additional targeted commands:
  - `cd packages/connectanum_router && dart test test/hook/build_hook_test.dart`
  - `cd packages/connectanum_client && dart test test/hook/build_hook_test.dart test/transport/native/native_library_loader_test.dart`

## Decision Log

- 2026-04-22: Prefer an environment-based packaging contract over inventing a
  package-specific config format. The runtime already honors
  `CONNECTANUM_NATIVE_LIB`, so the hooks should either reuse that path or stay
  out of the way entirely.
- 2026-04-22: Keep the explicit skip knob separate from
  `CONNECTANUM_NATIVE_LIB`. A concrete path should bundle that library without
  Cargo, while skip mode should allow system-library deployments to rely on the
  runtime loader alone.
- 2026-04-22: Align the client runtime loader with the router loader by
  falling back to the bare platform library name after hook/local-build probes.
  Without that, `CONNECTANUM_SKIP_NATIVE_BUILD=1` would still leave the client
  path unable to use a system-installed `ct_ffi`.

## Handoff

- Completed. The hooks now have a stable local packaging contract:
  `CONNECTANUM_NATIVE_LIB` reuses a prebuilt binary, and
  `CONNECTANUM_SKIP_NATIVE_BUILD=1` suppresses Cargo for system/shared-library
  deployments. The remaining follow-on work is release/CI packaging for
  prebuilt artifacts and/or install-time native build hooks.

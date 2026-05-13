# Exec Plan: native-install-helper

Status: completed
Owner: Codex
Created: 2026-04-22
Last updated: 2026-04-22

## Goal

Provide an explicit downstream install helper for hosted `ct_ffi` release
bundles so consumers can prefetch the native asset without Cargo or manual
archive extraction and then wire the resulting path into
`CONNECTANUM_NATIVE_LIB`.

## Scope

- In scope:
  - Add package entrypoints for `connectanum_router` and `connectanum_client`
    that download, checksum-verify, and extract a hosted native bundle into a
    deterministic app-local cache path.
  - Cover the install-helper and explicit hook contract with focused tests.
  - Update docs/state to record the pragmatic resolution of the
    install-time-acquisition follow-up.
- Out of scope:
  - Automatic execution during plain `dart pub get`.
  - Detached/offline signatures.
  - Windows native release assets.

## Files Expected To Change

- `packages/connectanum_router/tool/install_native.dart`
- `packages/connectanum_client/tool/install_native.dart`
- `packages/connectanum_router/lib/src/native_release_installer.dart`
- `packages/connectanum_client/lib/src/native_release_installer.dart`
- `packages/connectanum_router/hook/build.dart`
- `packages/connectanum_client/hook/build.dart`
- `packages/connectanum_router/test/hook/build_hook_test.dart`
- `packages/connectanum_client/test/hook/build_hook_test.dart`
- `packages/connectanum_router/test/hook/install_native_test.dart`
- `packages/connectanum_client/test/hook/install_native_test.dart`
- `README.md`
- `docs/deployment.md`
- `docs/project_state.md`
- `docs/exec-plans/*.md`
- `ROADMAP_NEXT.md`

## Preconditions

- Hosted Linux/macOS `ct_ffi` release bundles and `.sha256` sidecars already
  exist on GitHub Releases.
- The current release-tag hook path and attestation flow are already validated.
- `bin/test-fast` is currently red only because the new release-download hook
  path introduced analyzer warnings that should be fixed as part of this work.

## Plan

1. Clean up the current hook analyzer warnings and extract the hosted-bundle
   install logic into package-local helpers that the new CLI can use without
   importing hook-only build machinery.
2. Add `dart run connectanum_router:tool/install_native.dart` and
   `dart run connectanum_client:tool/install_native.dart` helpers that
   download, checksum-verify, and extract the host-native library into a
   deterministic app-local cache location.
3. Keep the existing hook contract explicit (`CONNECTANUM_NATIVE_LIB` or
   `CONNECTANUM_NATIVE_RELEASE_TAG`) and update tests and docs/state around the
   install-helper path, then rerun the canonical verification flow.

## Verification

- `bin/test-fast`
- `dart test packages/connectanum_router/test/hook/build_hook_test.dart -r expanded`
- `dart test packages/connectanum_router/test/hook/install_native_test.dart -r expanded`
- `dart test packages/connectanum_client/test/hook/build_hook_test.dart -r expanded`
- `dart test packages/connectanum_client/test/hook/install_native_test.dart -r expanded`
- `bin/verify`

## Decision Log

- 2026-04-22: Treat the unresolved install-time-acquisition item pragmatically:
  instead of unsupported `dart pub get` automation, provide explicit package
  install helpers that print the installed library path for
  `CONNECTANUM_NATIVE_LIB`.
- 2026-04-22: Drop automatic hook cache reuse after testing showed a Dart
  native-assets bundler bug on this macOS setup when relying on that path
  during package-root `dart test`; keep the supported contract explicit
  instead.

## Handoff

- `dart run connectanum_router:tool/install_native.dart --tag <release-tag>`
  and `dart run connectanum_client:tool/install_native.dart --tag <release-tag>`
  now download, checksum-verify, and extract the hosted `ct_ffi` bundle for the
  current host into `.dart_tool/connectanum/native/<host-triple>/`.
- Both commands print the installed library path on stdout so deployment
  scripts can capture it directly into `CONNECTANUM_NATIVE_LIB`.
- The hook/download implementation was split from the runtime binaries so the
  package install helpers no longer import hook-only build machinery.
- Verification that passed for this milestone:
  - `dart analyze packages/connectanum_router/tool/install_native.dart packages/connectanum_client/tool/install_native.dart packages/connectanum_router/lib/src/native_release_installer.dart packages/connectanum_client/lib/src/native_release_installer.dart packages/connectanum_router/test/hook/install_native_test.dart packages/connectanum_client/test/hook/install_native_test.dart`
  - `dart test packages/connectanum_router/test/hook/build_hook_test.dart -r expanded`
  - `dart test packages/connectanum_router/test/hook/install_native_test.dart -r expanded`
  - `dart test packages/connectanum_client/test/hook/build_hook_test.dart -r expanded`
  - `dart test packages/connectanum_client/test/hook/install_native_test.dart -r expanded`
  - `bin/test-fast`
  - `bin/verify`

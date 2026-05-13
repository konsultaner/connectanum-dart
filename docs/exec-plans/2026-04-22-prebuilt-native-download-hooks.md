# Exec Plan: prebuilt-native-download-hooks

Status: completed
Owner: Codex
Created: 2026-04-22
Last updated: 2026-04-22

## Goal

Let the router/client build hooks acquire prebuilt `ct_ffi` release bundles
directly from the hosted GitHub release path when explicitly requested, so
downstream consumers can avoid local Cargo builds and manual archive
extraction.

## Scope

- In scope:
  - Add an opt-in release-download path to both package build hooks.
  - Verify the downloaded archive against its published SHA-256 checksum before
    bundling the native library.
  - Document the new environment contract and refresh project state.
- Out of scope:
  - Automatic network fetches without an explicit opt-in.
  - Detached/offline signatures.
  - Windows release assets.
  - True `dart pub get`-time execution; Dart hooks currently run on
    `run`/`build`/`test`.

## Files Expected To Change

- `packages/connectanum_router/hook/build.dart`
- `packages/connectanum_client/hook/build.dart`
- `packages/connectanum_router/test/hook/build_hook_test.dart`
- `packages/connectanum_client/test/hook/build_hook_test.dart`
- `packages/connectanum_router/pubspec.yaml`
- `packages/connectanum_client/pubspec.yaml`
- `README.md`
- `docs/deployment.md`
- `docs/project_state.md`
- `docs/exec-plans/*.md`
- `ROADMAP_NEXT.md`

## Preconditions

- Release bundles already exist on GitHub Releases as
  `ct-ffi-<host-triple>.tar.gz` plus `.sha256`.
- Hosted release publishing and GitHub artifact attestations are already
  validated.
- The hook path must stay compatible with the existing local Cargo build flow
  and `CONNECTANUM_NATIVE_LIB` override.

## Plan

1. Add an explicit release-tag/repository environment contract to both build
   hooks so they can download, checksum-verify, extract, and bundle the
   appropriate host-native library without invoking Cargo.
2. Add focused hook tests for the new prebuilt-download path and keep the
   current local-library/system-library behavior unchanged.
3. Update docs/state, run `bin/verify`, and close out the milestone with the
   exact verification that passed.

## Verification

- `bin/test-fast`
- `cd packages/connectanum_router && dart test test/hook/build_hook_test.dart -r expanded`
- `cd packages/connectanum_client && dart test test/hook/build_hook_test.dart -r expanded`
- `bin/verify`

## Decision Log

- 2026-04-22: Use an explicit release-tag environment variable instead of
  implicit network fallback so local development keeps preferring Cargo builds
  and downstream packaging can opt into hosted binaries intentionally.
- 2026-04-22: Treat “install-time build hooks” pragmatically as
  hook-managed prebuilt acquisition on `run`/`build`/`test`, because the Dart
  SDK’s current hook automation does not run on plain `dart pub get`.

## Handoff

- Users can now set `CONNECTANUM_NATIVE_RELEASE_TAG=<tag>` before
  `dart run` / `dart test` and let the existing router/client hooks download,
  checksum-verify, extract, and bundle the matching host-native
  `ct_ffi` release archive from GitHub Releases.
- `CONNECTANUM_NATIVE_RELEASE_REPOSITORY=<owner/repo>` overrides the default
  release source (`konsultaner/connectanum-dart`) when a downstream mirror or
  fork hosts the same release layout.
- The explicit `CONNECTANUM_NATIVE_LIB`,
  `CONNECTANUM_SKIP_NATIVE_BUILD=1`, and release-tag paths no longer require a
  local `native/transport` workspace checkout; only the Cargo build path still
  searches for `native/transport/Cargo.toml`.
- Verification that passed for this milestone:
  - `bin/test-fast`
  - `cd packages/connectanum_router && dart test test/hook/build_hook_test.dart -r expanded`
  - `cd packages/connectanum_client && dart test test/hook/build_hook_test.dart -r expanded`
  - `bin/verify`

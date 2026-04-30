# Exec Plan: native install command readability

Status: completed
Owner: Codex
Created: 2026-04-30
Last updated: 2026-04-30

## Goal

Keep the native release/download path human-readable and executable by removing
the remaining invalid `dart run <package>:tool/install_native.dart` guidance
from public install surfaces.

## Scope

- In scope:
  - Generated native bundle README text in `bin/package-native-artifact`.
  - `install_native.dart` usage text for router and client packages.
  - A fast regression that catches the invalid package-target command form in
    release-facing install guidance.
  - Current project-state checkpoint for the slice.
- Out of scope:
  - Changing native bundle layout or release tags.
  - Publishing releases, mutating GHCR packages, or changing branch protection.
  - Reworking the hook-managed `CONNECTANUM_NATIVE_RELEASE_TAG` path.

## Files Expected To Change

- `bin/package-native-artifact`
- `bin/test-fast`
- `bin/test-all`
- `packages/connectanum_router/tool/install_native.dart`
- `packages/connectanum_client/tool/install_native.dart`
- `tool/test_package_native_artifact.py`
- `docs/project_state.md`
- `docs/exec-plans/2026-04-30-native-install-command-readability.md`

## Preconditions

- Hosted GitHub CI/deployment-chain audit is clean for current head `4d32688`.
- Pre-change `bin/test-fast` passed locally on 2026-04-30.

## Plan

1. Replace remaining invalid package-target install commands with source-checkout
   file-path commands.
2. Add a focused Python regression and wire it into fast/full local verification.
3. Run targeted checks, `bin/verify`, and update this plan/state before handoff.

## Verification

- `bin/test-fast` passed before edits.
- `python3 tool/test_package_native_artifact.py`
- `dart packages/connectanum_router/tool/install_native.dart --help`
- `dart packages/connectanum_client/tool/install_native.dart --help`
- `python3 -m py_compile tool/test_package_native_artifact.py`
- `bash -n bin/package-native-artifact bin/test-fast bin/test-all`
- `git diff --check`
- `bin/verify`

## Decision Log

- 2026-04-30: Verified `dart run connectanum_router:tool/install_native.dart
  --help` fails with `Could not find file`, so the package-target command form
  should not appear in public install guidance.

## Handoff

- Completed locally. Commit, push, then watch hosted GitHub CI and the package
  dry-run as the next deployment-chain step.

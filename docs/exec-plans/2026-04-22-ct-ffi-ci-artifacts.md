# Exec Plan: ct-ffi-ci-artifacts

Status: completed
Owner: Codex
Created: 2026-04-22
Last updated: 2026-04-22

## Goal

Publish reusable `ct_ffi` native build artifacts from GitHub Actions so
deployments and downstream testing can consume prebuilt Linux/macOS libraries
without rebuilding Rust first.

## Scope

- In scope:
  - A reusable repo-local packaging script for `ct_ffi` release artifacts.
  - A dedicated GitHub Actions workflow that builds and uploads packaged
    Linux/macOS artifacts.
  - Documentation for how to download and use the uploaded artifacts with
    `CONNECTANUM_NATIVE_LIB`.
  - Refreshing project state and roadmap notes for the new CI packaging path.
- Out of scope:
  - GitHub Releases publishing or signing.
  - Windows artifact production.
  - Install-time (`dart pub get`) native build hooks.

## Files Expected To Change

- `bin/common.sh`
- `bin/package-native-artifact`
- `.github/workflows/*.yml`
- `README.md`
- `docs/deployment.md`
- `native/transport/README.md`
- `docs/project_state.md`
- `ROADMAP_NEXT.md`

## Preconditions

- GitHub Actions remains the primary hosted CI path for this branch.
- Linux and macOS hosted runners are sufficient for the first artifact matrix.

## Plan

1. Add a deterministic local packaging script that builds `ct_ffi`, stages the
   library plus metadata/license files, and emits archive/checksum paths.
2. Add a GitHub Actions workflow that runs the script on Linux and macOS and
   uploads the resulting bundles as workflow artifacts.
3. Document how the artifacts fit the existing `CONNECTANUM_NATIVE_LIB`
   contract, then run `bin/verify` plus a local packaging smoke check.

## Verification

- `bin/test-fast`
- `bin/verify`
- Additional targeted commands:
  - `bin/package-native-artifact`

## Decision Log

- 2026-04-22: Use a repo-local shell script for packaging instead of embedding
  all logic in workflow YAML so local verification and CI produce the same
  archive layout.
- 2026-04-22: Keep the initial hosted workflow on `workflow_dispatch` plus tag
  pushes only, so release-grade packaging stays explicit and does not inflate
  every branch CI run.

## Handoff

- Completed. `bin/package-native-artifact` now builds host-native `ct_ffi`
  release bundles, and `.github/workflows/native-artifacts.yml` publishes the
  Linux/macOS archives, checksums, and manifests as workflow artifacts.
- Remaining follow-up: promote these bundles into durable signed releases
  and/or add an install-time acquisition/build path for downstream package
  consumers.

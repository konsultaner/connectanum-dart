# Exec Plan: ct-ffi-artifact-attestations

Status: completed
Owner: Codex
Created: 2026-04-22
Last updated: 2026-04-22

## Goal

Add release-grade provenance attestations for the packaged `ct_ffi`
Linux/macOS bundles so downstream consumers can verify hosted release assets
against GitHub's attestation service instead of relying on unsigned archives
alone.

## Scope

- In scope:
  - Extend the `Native Artifacts` workflow so each packaged archive/checksum/
    manifest set is attested on the runner that built it.
  - Document how consumers verify the released archives with GitHub
    attestations.
  - Refresh project state and roadmap notes for the new attested release
    baseline.
- Out of scope:
  - Detached/offline signature files.
  - Windows release artifacts.
  - Install-time (`dart pub get`) native acquisition/build hooks.

## Files Expected To Change

- `.github/workflows/native-artifacts.yml`
- `README.md`
- `docs/deployment.md`
- `docs/project_state.md`
- `docs/exec-plans/*.md`
- `ROADMAP_NEXT.md`

## Preconditions

- The hosted release-publish path is already validated on GitHub for
  `Native Artifacts`.
- The packaged artifacts already have stable, deterministic filenames from
  `bin/package-native-artifact`.
- The public GitHub repository can use GitHub artifact attestations.

## Plan

1. Add GitHub artifact attestation generation to the matrix packaging job so
   each packaged archive/checksum/manifest set gets provenance attached at build
   time.
2. Update docs and project state to describe the new verification path and the
   remaining follow-ups after attestations land.
3. Run `bin/verify`, validate the workflow once on GitHub, then close out the
   plan with the exact hosted run result.

## Verification

- `bin/test-fast`
- `bin/verify`
- One hosted GitHub Actions `Native Artifacts` run after the attestation
  workflow change lands

## Decision Log

- 2026-04-22: Use GitHub's built-in artifact attestation flow instead of adding
  a separate signing toolchain first, because it fits the existing GitHub
  release workflow and gives immediate provenance coverage for public releases.
- 2026-04-22: Attest the packaged archive, checksum, and manifest together on
  each matrix runner so the same provenance record covers the shipped archive
  plus the metadata files consumers use alongside it.

## Handoff

- Completed. `Native Artifacts` now generates GitHub artifact attestations for
  each packaged Linux/macOS archive/checksum/manifest set via `actions/attest`.
- Hosted validation passed on GitHub Actions run `24757138619` for validation
  tag `ct-ffi-v2026.04.22-validation.043206-attest`, with both `ct_ffi`
  matrix jobs generating attestations successfully and `Publish GitHub Release`
  remaining green.
- Local verification also passed with `bin/test-fast`, local YAML parsing of
  `.github/workflows/native-artifacts.yml`, and `bin/verify`.
- Remaining follow-up: install-time native acquisition/build hooks, plus
  detached/offline signatures only if GitHub-hosted attestations are not
  sufficient for downstream consumers.

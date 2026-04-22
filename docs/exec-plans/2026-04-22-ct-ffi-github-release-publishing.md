# Exec Plan: ct-ffi-github-release-publishing

Status: completed
Owner: Codex
Created: 2026-04-22
Last updated: 2026-04-22

## Goal

Publish the packaged `ct_ffi` Linux/macOS archives to durable GitHub Releases so
downstream deployment and install flows can rely on stable release assets
instead of workflow-artifact retention only.

## Scope

- In scope:
  - Extend the existing `Native Artifacts` workflow to create/update GitHub
    Releases for release tags and explicit manual release-tag inputs.
  - Document how the release assets fit the existing
    `CONNECTANUM_NATIVE_LIB` contract.
  - Refresh project state and roadmap notes for the new release-publishing
    baseline.
  - Restore the test files to the repo's `@TestOn` + `library;` pattern so the
    analyzer output stays quiet.
- Out of scope:
  - Artifact signing/attestation.
  - Windows release artifacts.
  - Install-time (`dart pub get`) native build hooks.

## Files Expected To Change

- `.github/workflows/native-artifacts.yml`
- `README.md`
- `docs/deployment.md`
- `docs/project_state.md`
- `docs/exec-plans/*.md`
- `ROADMAP_NEXT.md`
- `packages/connectanum_client/test/**/*.dart`
- `packages/connectanum_router/test/**/*.dart`

## Preconditions

- The native artifact workflow already produces valid Linux/macOS archives via
  `bin/package-native-artifact`.
- GitHub-hosted runners can authenticate release operations with the workflow
  `GITHUB_TOKEN`.

## Plan

1. Add release-publishing logic on top of the existing native artifact workflow
   so tag-triggered runs publish the packaged assets to GitHub Releases and
   manual runs can do the same when given an explicit release tag.
2. Update the user-facing docs and roadmap/state files to describe the durable
   release path and narrow the remaining packaging follow-ups to signing and
   install-time acquisition/build hooks.
3. Run `bin/verify`, then close out the plan with the exact release-publishing
   contract that passed.

## Verification

- `bin/test-fast`
- `bin/verify`

## Decision Log

- 2026-04-22: Reuse the existing `Native Artifacts` workflow as the release
  entrypoint instead of adding a second parallel workflow, so artifact upload
  and GitHub release publishing stay tied to the same packaging script and
  trigger surface.
- 2026-04-22: Do not rewrite existing GitHub Release titles or notes on reruns;
  existing releases only get refreshed assets so ordinary `v*` repository
  releases keep their broader release metadata.

## Handoff

- Completed. The native artifact workflow now supports durable GitHub Release
  publishing for tag-triggered runs and explicit manual release-tag dispatches,
  while still uploading workflow artifacts for ordinary manual packaging runs.
- Remaining follow-up: asset signing/attestation, install-time acquisition/build
  hooks, and the first live GitHub Actions confirmation of the new release job.

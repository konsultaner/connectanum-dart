# Router Image Dry-Run Audit

Status: in progress

## Goal

Make release-candidate audits require hosted Router Image dry-run evidence before
treating the router image deployment chain as RC-ready.

## Scope

- In scope: read-only audit behavior for the `Router Image` workflow, preview
  artifact validation, dry-run/non-publish metadata validation, and relevance
  checks against checked-out router-image inputs.
- Out of scope: publishing router images, creating RC tags, or mutating GitHub
  Releases.

## Implementation

- `bin/audit-github-deployment-chain` now accepts
  `--show-router-image-dry-run` and
  `--require-clean-router-image-dry-run`.
- The Router Image gate checks the latest branch workflow run, requires the
  expected `Publish Router Image` job to complete successfully, downloads the
  `router-image-preview` artifact, and verifies the metadata is a non-mutating
  dry-run with `publish=false`, `provenance=false`, and `sbom=false`.
- RC readiness now includes the hosted Router Image dry-run gate alongside CI,
  Dart package dry-run, native release evidence, workflow visibility, package
  visibility, and RC prerelease state.

## Verification

- `bin/test-fast` passed before edits.
- `bash -n bin/audit-github-deployment-chain` passed.
- `bin/audit-github-deployment-chain --help | rg -- '--show-router-image-dry-run|--require-clean-router-image-dry-run|hosted router image'`
  passed.
- `bin/audit-github-deployment-chain --branch codex/post-rc-production-readiness --run-limit 1 --show-router-image-dry-run`
  passed as a show-only audit and reported that no Router Image dry-run exists
  yet for the branch.
- `bin/verify` passed on 2026-05-13.
- Hosted Router Image dry-run and final deployment-chain audit pending after
  push.

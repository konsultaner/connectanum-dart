# Exec Plan: native-signature-bundles

Status: completed
Owner: Codex
Created: 2026-04-22
Last updated: 2026-04-22

## Goal

Add detached, offline-verifiable signature bundles for the packaged `ct_ffi`
release assets without introducing a long-lived private signing key secret.

## Scope

- In scope:
  - Extend the existing `Native Artifacts` GitHub Actions workflow so each
    packaged archive, checksum, and manifest also receives a Sigstore blob
    bundle.
  - Upload those bundle files alongside the existing workflow artifacts and
    GitHub Release assets.
  - Document offline verification with `cosign verify-blob` and record the new
    workflow contract in project state.
- Out of scope:
  - Managing a self-hosted GPG/minisign private key.
  - Windows native release assets.
  - Replacing GitHub artifact attestations; this work adds a detached/offline
    verification path on top of them.

## Files Expected To Change

- `.github/workflows/native-artifacts.yml`
- `README.md`
- `docs/deployment.md`
- `docs/project_state.md`
- `docs/exec-plans/*.md`
- `ROADMAP_NEXT.md`

## Preconditions

- The `Native Artifacts` workflow already produces Linux/macOS release bundles
  and GitHub artifact attestations.
- GitHub Actions OIDC is already enabled for the packaging jobs
  (`id-token: write`).
- `bin/test-fast` is green before this change.

## Plan

1. Check in this active plan and update project state to point at it.
2. Install Cosign in the `ct_ffi` workflow jobs, generate keyless blob bundles
   for the archive/checksum/manifest outputs, and upload those bundles with the
   rest of the packaged assets.
3. Update docs/state to describe the new detached/offline verification flow,
   run `bin/verify`, and checkpoint the milestone.

## Verification

- `bin/test-fast`
- `ruby -e "require 'yaml'; YAML.load_file('.github/workflows/native-artifacts.yml'); puts 'yaml_ok'"`
- `bin/verify`

## Decision Log

- 2026-04-22: Use Sigstore keyless blob bundles instead of a repository-managed
  private signing key so the release-signing path does not depend on a new
  secret.
- 2026-04-22: Sign the packaged archive, checksum, and manifest individually so
  the detached verification story matches the existing attestation subject set.

## Handoff

- The `Native Artifacts` workflow now installs Cosign in each packaging job,
  signs the packaged archive/checksum/manifest into detached
  `<asset>.sigstore.json` bundles, verifies those bundles in CI, and uploads
  them with the existing workflow artifacts and GitHub Release assets.
- The release/deployment docs now describe both verification paths:
  `gh attestation verify` for GitHub-hosted attestations and
  `cosign verify-blob --bundle <asset>.sigstore.json` for detached/offline
  verification.
- Verification that passed for this milestone:
  - `bin/test-fast`
  - `ruby -e "require 'yaml'; YAML.load_file('.github/workflows/native-artifacts.yml'); puts 'yaml_ok'"`
  - `bin/verify`

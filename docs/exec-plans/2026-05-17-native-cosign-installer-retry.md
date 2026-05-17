# Exec Plan: Native Cosign Installer Retry

Status: complete locally; hosted v4.1.2 evidence pending after push
Owner: Codex
Created: 2026-05-17
Last updated: 2026-05-17

## Goal

Reduce release-chain flakiness in the `Native Artifacts` workflow by moving the
Cosign installer to an upstream release that retries transient download
failures and avoids the stale custom-version download path before signing
native bundles.

## Scope

- In scope:
  - Update the Native Artifacts workflow Cosign installer action version.
  - Preserve the upstream installer's digest and signature verification model.
  - Verify the change locally with the standard fast and full gates.
  - Refresh project state with the deployment-hardening result.
- Out of scope:
  - Creating or mutating RC tags.
  - Publishing native bundles or router images.
  - Changing signing, bundle, or release-note semantics.

## Plan

1. Confirm local baseline with `bin/test-fast`.
2. Update `.github/workflows/native-artifacts.yml` to the Cosign installer
   release that includes retry handling for transient curl downloads.
3. Run workflow-sensitive local checks plus `bin/verify`.
4. Push the implementation and refresh hosted deployment-chain evidence if the
   workflow change requires it for handoff.

## Verification

- `bin/test-fast` passed before edits on 2026-05-17.
- A second `bin/test-fast` passed before the v4.1.2 follow-up on 2026-05-17.
- `git diff --check` passed after edits on 2026-05-17.
- Private-name scan on the touched workflow/state/plan paths passed on
  2026-05-17.
- `bin/verify` passed after the v4.1.2 follow-up on 2026-05-17.

## Decision Log

- 2026-05-17: Prefer upgrading the maintained upstream installer action over
  carrying a local Cosign download script, because the upstream release keeps
  installer integrity checks and adds retry handling where the transient
  failure occurred.
- 2026-05-17: Hosted Native Artifacts dry-run #25979718422 proved v4.1.0 was
  not sufficient on Windows x64: the installer retried the
  `v3.0.3/cosign-windows-amd64.exe-kms.sigstore.json` download, but GitHub
  returned repeated 502 responses. Move to `sigstore/cosign-installer@v4.1.2`
  instead of adding a local downloader, because v4.1.2 defaults to Cosign
  `v3.0.6`, matching its pinned bootstrap version and avoiding that additional
  custom-version KMS bundle download while retaining upstream digest checks.

## Handoff

- The Native Artifacts workflow now uses
  `sigstore/cosign-installer@v4.1.2`.
- Local verification is clean. Because this is workflow-sensitive, hosted
  Native Artifacts evidence should be refreshed after the implementation commit
  is pushed.

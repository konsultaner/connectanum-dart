# Exec Plan: MCP Package Release Readiness

Status: complete; hosted evidence clean
Owner: Codex
Created: 2026-05-04
Last updated: 2026-05-04

## Goal

Make the private `connectanum_mcp` package fail the GitHub deployment chain if
its archive becomes invalid or warning-prone, without making it publicly
publishable before the release order is approved.

## Scope

In scope:

- Add GitHub Actions coverage for
  `bin/dart-package-publish-dry-run --include-private connectanum_mcp`.
- Keep `connectanum_mcp` private via `publish_to: none`.
- Remove the current private-package dry-run warning by adding required package
  release metadata.
- Bundle verification/state notes with the workflow/package change.

Out of scope:

- Publishing `connectanum_mcp` to pub.dev.
- Changing package dependency release order.
- Changing router-hosted MCP runtime behavior.

## Files Expected To Change

- `.github/workflows/dart-package-publish.yml`
- `packages/connectanum_mcp/CHANGELOG.md`
- `docs/project_state.md`
- `docs/exec-plans/2026-05-04-mcp-package-release-readiness.md`

## Plan

1. Reproduce the private-package dry-run warning.
2. Add a dedicated GitHub workflow step for the private MCP package archive.
3. Add the missing MCP package changelog.
4. Run focused package dry-runs and full local verification.
5. Push and collect hosted GitHub deployment-chain evidence.

## Verification

- Pre-change `bin/test-fast` passed on 2026-05-04.
- The focused pre-change command
  `bin/dart-package-publish-dry-run --include-private connectanum_mcp`
  reproduced the blocker: the package archive failed the zero-warning gate
  because `packages/connectanum_mcp/CHANGELOG.md` was missing.
- Focused checks passed after implementation on 2026-05-04:
  `bin/dart-package-publish-dry-run --include-private connectanum_mcp` and
  `bin/dart-package-publish-dry-run`; both reported zero package warnings.
- Full local `bin/verify` passed on 2026-05-04 after the workflow/package
  change. It included formatting, Rust native/FFI tests, Python
  package-artifact checks, MCP package tests, client tests, auth-server tests,
  bench integration tests, full router package tests including router-hosted
  MCP and `remote_auth_integration_test`, zero-copy router checks, and Chrome
  Dart2Wasm WebSocket transport tests.
- Hosted GitHub evidence for `e2ed55d` is clean: `CI` run `25303581665`
  completed successfully with `Fast Checks` and `Full Verify`, the hosted CI
  log scan found no warning, deprecation, skipped-test, reset,
  connection-noise, panic, or failure patterns, and `Dart Package Publish Dry
  Run` run `25303581667` completed successfully with the new
  `Validate MCP package release readiness` step. Strict deployment-chain audit
  passed after the push; Native Artifacts dry-run `25192553399` remains clean
  and relevant because no native-release-sensitive paths changed.

## Decision Log

- 2026-05-04: Keep the MCP package private but validate it explicitly in the
  GitHub package dry-run workflow. This gives downstream application readiness
  evidence without forcing a pub.dev release decision.

## Handoff

Complete. Commit `e2ed55d` was pushed to both remotes, and hosted GitHub
deployment-chain evidence is clean. Remaining deployment-chain findings are
operator/setup items: protect the branch, promote
`.github/workflows/router-image.yml` through the default branch for Actions API
visibility, and publish the router container package when that release lane is
enabled.

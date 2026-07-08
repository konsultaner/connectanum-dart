# Exec Plan: Router Package Publishability

Status: complete
Owner: Codex
Created: 2026-07-08
Last updated: 2026-07-08

## Problem

Router-hosted MCP is the current downstream application readiness priority, but
the `connectanum_router` package remained non-publishable after
`connectanum_core`, `connectanum_client`, and `connectanum_mcp` became
publishable. The remaining router package dry-run blockers were local path
dependencies on those already publishable packages plus `publish_to: none`.

## Scope

- Promote `connectanum_router` into the modular publishable slice by using
  hosted constraints for already publishable runtime dependencies.
- Keep `connectanum_auth_server` and `connectanum_bench` private until their
  own explicit release slices.
- Update the Dart package dry-run and deployment-chain regression fixtures so
  strict readiness covers the router package.
- Do not publish to pub.dev, claim package names, configure publisher ownership,
  create tags, or deploy artifacts in this slice.

## Milestones

- [x] Run baseline `bin/test-fast` before changing router package metadata.
- [x] Confirm the router package include-private dry-run only fails for runtime
  path dependencies on already publishable packages.
- [x] Switch `connectanum_router` runtime dependencies to hosted constraints and
  remove `publish_to: none`.
- [x] Update release tooling regressions for the new publishable slice.
- [x] Commit the package/test/docs bundle, then run clean strict router and
  current-slice package dry-runs plus full `bin/verify`.
- [x] Push code/config/package changes and inspect hosted CI/package dry-run
  evidence needed for handoff.

## Verification

- `bin/test-fast`
- `bin/dart-package-publish-dry-run --include-private --show-release-plan connectanum_router`
- `python3 -m unittest tool.test_dart_package_publish_dry_run`
- `python3 -m unittest tool.test_audit_github_deployment_chain`
- `dart analyze packages/connectanum_router`
- `python3 tool/check_public_artifact_references.py`
- `bash -n bin/dart-package-publish-dry-run bin/audit-github-deployment-chain`
- `git diff --check`
- Post-commit: `bin/dart-package-publish-dry-run --strict-release-ready --show-release-plan connectanum_router`
- Post-commit: `bin/dart-package-publish-dry-run --strict-release-ready --show-release-plan`
- Post-commit: `bin/verify`

## Decision Log

- 2026-07-08: Baseline `bin/test-fast` passed. The pre-change router package
  include-private dry-run failed only for local path dependencies on
  `connectanum_core`, `connectanum_client`, and `connectanum_mcp`; no changelog
  or false-secret archive blockers remained. The implementation switches those
  runtime dependencies to hosted constraints matching the current publishable
  modular versions and removes `publish_to: none`, while leaving auth-server and
  benchmark packages private.
- 2026-07-08: Commit `da55701` promoted `connectanum_router` into the
  publishable modular package slice. Clean strict router package dry-run, clean
  strict current publishable-slice dry-run, and full local `bin/verify` passed.
  Hosted CI `28937100711`, Dart Package Publish Dry Run `28937100685`, and
  WAMP Profile Benchmarks `28937100701` passed at `da55701`. The clean
  deployment-chain audit passed with CI/log, Dart package dry-run, WAMP
  benchmark, workflow visibility, and router-package requirements; strict audit
  still fails only for the known unprotected `add-router` branch policy gap.

# Exec Plan: Bench Package Publishability

Status: complete
Owner: Codex
Created: 2026-07-08
Last updated: 2026-07-08

## Problem

The approved modular pub.dev package strategy now includes the runtime package
graph through `connectanum_auth_server`, but `connectanum_bench` remains private
despite clearing its concrete archive blockers. That leaves benchmark tooling
outside the same publishability evidence chain as the shipped router and MCP
packages.

## Scope

- Promote `connectanum_bench` into the modular publishable slice by using hosted
  constraints for already publishable runtime dependencies.
- Update the Dart package dry-run and deployment-chain regression fixtures so
  strict readiness covers the bench package and the full modular graph.
- Do not publish to pub.dev, claim package names, configure publisher ownership,
  create tags, or deploy artifacts in this slice.

## Milestones

- [x] Run baseline `bin/test-fast` before changing bench package metadata.
- [x] Confirm the bench package include-private dry-run only fails for runtime
  path dependencies on already publishable packages.
- [x] Switch `connectanum_bench` runtime dependencies to hosted constraints and
  remove `publish_to: none`.
- [x] Update release tooling regressions for the full publishable modular graph.
- [x] Commit the package/test/docs bundle, then run clean strict bench and full
  package-graph dry-runs plus full `bin/verify`.
- [x] Push code/config/package changes and inspect hosted CI/package dry-run
  evidence needed for handoff.

## Verification

- `bin/test-fast`
- `bin/dart-package-publish-dry-run --include-private --show-release-plan connectanum_bench`
- `python3 -m unittest tool.test_dart_package_publish_dry_run`
- `python3 -m unittest tool.test_audit_github_deployment_chain`
- `dart analyze packages/connectanum_bench`
- `python3 tool/check_public_artifact_references.py`
- `bash -n bin/dart-package-publish-dry-run bin/audit-github-deployment-chain`
- `git diff --check`
- Post-commit: `bin/dart-package-publish-dry-run --strict-release-ready --show-release-plan connectanum_bench`
- Post-commit: `bin/dart-package-publish-dry-run --strict-release-ready --show-release-plan`
- Post-commit: `bin/verify`

## Decision Log

- 2026-07-08: Baseline `bin/test-fast` passed. The pre-change bench package
  include-private dry-run failed only for local path dependencies on
  `connectanum_router`, `connectanum_core`, `connectanum_client`, and
  `connectanum_auth_server`; no changelog or false-secret archive blockers
  remained. The implementation switches those runtime dependencies to hosted
  constraints matching the current publishable modular versions and removes
  `publish_to: none`.
- 2026-07-08: Focused release-tooling tests, audit-tool tests, bench package
  analysis, public-artifact reference scanning, shell syntax checks, and
  whitespace checks passed before commit. The uncommitted bench package dry-run
  now reports only the expected dirty-package warning for the modified
  `pubspec.yaml`, so clean strict package dry-runs and full `bin/verify` remain
  post-commit gates.
- 2026-07-08: Commit `4ef668b` made `connectanum_bench` publishable and left
  no private workspace packages in the modular release plan. Clean strict bench
  and full package-graph dry-runs passed with zero warnings; full local
  `bin/verify` passed. The branch was pushed to `origin` and `github`. Hosted
  CI `28944706690`, Dart Package Publish Dry Run `28944706698`, and WAMP
  Profile Benchmarks `28944706579` passed at `4ef668b`. The clean
  deployment-chain audit passed with CI/log, Dart package dry-run, WAMP
  benchmark, workflow visibility, and router-package requirements. The strict
  audit still fails only for the known operator-owned `add-router`
  branch-protection gap.

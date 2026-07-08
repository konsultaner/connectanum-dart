# Exec Plan: Auth Server Package Publishability

Status: active
Owner: Codex
Created: 2026-07-08
Last updated: 2026-07-08

## Problem

The modular public package slice now includes `connectanum_router`, but
`connectanum_auth_server` remains private even though its only current
publish-blocking dependencies are on already publishable packages. That leaves
remote-auth packaging out of the downstream application readiness path.

## Scope

- Promote `connectanum_auth_server` into the modular publishable slice by using
  hosted constraints for already publishable runtime dependencies.
- Keep `connectanum_bench` private until its own explicit release slice.
- Update the Dart package dry-run and deployment-chain regression fixtures so
  strict readiness covers the auth-server package.
- Do not publish to pub.dev, claim package names, configure publisher
  ownership, create tags, or deploy artifacts in this slice.

## Milestones

- [x] Run baseline `bin/test-fast` before changing auth-server package metadata.
- [x] Confirm the auth-server package include-private dry-run only fails for
  runtime path dependencies on already publishable packages.
- [x] Switch `connectanum_auth_server` runtime dependencies to hosted
  constraints and remove `publish_to: none`.
- [x] Update release tooling regressions for the new publishable slice.
- [ ] Commit the package/test/docs bundle, then run clean strict auth-server
  and current-slice package dry-runs plus full `bin/verify`.
- [ ] Push code/config/package changes and inspect hosted CI/package dry-run
  evidence needed for handoff.

## Verification

- `bin/test-fast`
- `bin/dart-package-publish-dry-run --include-private --show-release-plan connectanum_auth_server`
- `python3 -m unittest tool.test_dart_package_publish_dry_run`
- `python3 -m unittest tool.test_audit_github_deployment_chain`
- `dart analyze packages/connectanum_auth_server`
- `python3 tool/check_public_artifact_references.py`
- `bash -n bin/dart-package-publish-dry-run bin/audit-github-deployment-chain`
- `git diff --check`
- Post-commit: `bin/dart-package-publish-dry-run --strict-release-ready --show-release-plan connectanum_auth_server`
- Post-commit: `bin/dart-package-publish-dry-run --strict-release-ready --show-release-plan`
- Post-commit: `bin/verify`

## Decision Log

- 2026-07-08: Baseline `bin/test-fast` passed. The pre-change auth-server
  package include-private dry-run failed only for local path dependencies on
  `connectanum_router` and `connectanum_core`; no changelog archive blockers
  remained. The implementation switches those runtime dependencies to hosted
  constraints matching the current publishable modular versions and removes
  `publish_to: none`, while leaving the benchmark package private.
- 2026-07-08: Focused release-tooling tests, audit-tool tests, auth-server
  package analysis, public-artifact reference scanning, shell syntax checks,
  and whitespace checks passed before commit. The uncommitted auth-server
  package dry-run reports only the expected dirty-package warning, so clean
  strict package dry-runs and full `bin/verify` remain post-commit gates.

# Exec Plan: Dart Package Public Release Readiness

Status: in_progress
Owner: Codex
Created: 2026-07-07
Last updated: 2026-07-07

## Problem

The Dart stack cannot be called a production-ready replacement for Java-core
consumer development while the public package graph is not installable from
pub.dev. The current strict release gate fails because the publishable
`connectanum_client` archive depends on private workspace package
`connectanum_core`.

## Scope

- Separate archive-quality blockers from operator release decisions.
- Keep `publish_to: none` unchanged until package-name ownership, publisher,
  public versions, and package naming are explicitly approved.
- Make `connectanum_core` ready for a future public package slice by fixing
  concrete `dart pub publish --dry-run` findings.
- Preserve current RC semantics: GitHub prerelease/router-image readiness can
  stay green while pub.dev release readiness remains blocked.

## Non-Goals

- Publishing to pub.dev.
- Claiming package names or configuring publisher ownership.
- Renaming packages or replacing the legacy public `connectanum` package
  without an explicit package migration decision.
- Making router, MCP, auth-server, or benchmark packages public in this slice.

## Milestones

- [x] Confirm the strict package gate still identifies the private
  `connectanum_core` dependency as the release blocker.
- [x] Confirm current pub.dev package-name state for the legacy and modular package
  names.
- [x] Make the private `connectanum_core` archive clear its concrete pre-publish
  blockers while keeping it private.
- [x] Re-run local verification and clean package-copy package dry-runs.
- [ ] Decide the package release strategy: publish modular packages in dependency
  order, keep using the legacy `connectanum` name for client compatibility, or
  provide a compatibility wrapper.

## Verification

- `bin/test-fast`
- `bin/dart-package-publish-dry-run --strict-release-ready --show-release-plan`
- `bin/dart-package-publish-dry-run --include-private connectanum_core`
- `bin/verify`
- Clean package-copy simulation: `git archive` the repo, overlay the new
  `connectanum_core` package metadata, then run
  `bin/dart-package-publish-dry-run --include-private connectanum_core`.

## Decision Log

- 2026-07-07: Hardened the release gate wording without changing package
  publishability. `bin/dart-package-publish-dry-run --strict-release-ready
  --show-release-plan` now prints a `Dart package release strategy decision
  required` section for the known private workspace dependency blocker and
  lists the explicit strategy choices: publish the modular dependency graph in
  order, keep the legacy public package name, or ship a compatibility wrapper.
  `bin/audit-github-deployment-chain` now requires and surfaces that section
  before classifying the strict Dart package failure as the known pub.dev
  deferral. Local `bin/test-fast`, focused release-tooling tests, the
  expected-failing strict dry-run for `connectanum_client`, the private
  `connectanum_core` dry-run, and full `bin/verify` passed. The package
  release strategy milestone remains open.
- 2026-07-07: Treat pub.dev installability as a Java-core replacement blocker,
  not merely an RC deferral. The strict release gate fails because
  `connectanum_client` depends on private `connectanum_core`. Current pub.dev
  API checks returned `200` for the legacy public `connectanum` package at
  `2.2.7` and `404` for `connectanum_client`, `connectanum_core`,
  `connectanum_router`, `connectanum_mcp`, and `connectanum_auth_server`, so
  package naming and ownership remain explicit decisions. `connectanum_core`
  preflight found two concrete archive issues: missing `CHANGELOG.md` and a
  false-positive fixture key in `test/authentication/cryptosign/keys.dart`.
  This slice adds the changelog and a scoped `false_secrets` allowlist while
  keeping `publish_to: none` in place. Baseline `bin/test-fast` passed before
  the change, full `bin/verify` passed after the change, and a clean
  package-copy dry-run passed for `connectanum_core` with zero warnings.

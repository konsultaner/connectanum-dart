# Exec Plan: Dart Package Public Release Readiness

Status: complete
Owner: Codex
Created: 2026-07-07
Last updated: 2026-07-08

## Problem

The Dart stack could not be called a production-ready replacement for Java-core
consumer development while the public package graph was not installable from
pub.dev. This plan resolved the concrete first publishable-slice blocker by
approving the modular-plus-compatibility package strategy and making
`connectanum_core` and `connectanum_mcp` publishable before router package
publishing.

## Scope

- Separate archive-quality blockers from operator release decisions.
- Keep remaining private package `publish_to: none` settings unchanged until
  package-name ownership, publisher, public versions, and package naming are
  explicitly approved for those slices.
- Make `connectanum_core` the first publishable modular package after the
  package strategy decision.
- Make `connectanum_mcp` publishable after its include-private dry-run has zero
  warnings and its public dependencies are already publishable.
- Make `connectanum_core` ready for the first public package slice by fixing
  concrete `dart pub publish --dry-run` findings.
- Remove concrete non-strategy archive blockers from the router-hosted MCP
  package path when found, while keeping package publishing disabled.
- Remove concrete non-strategy archive blockers from the auth-server package
  path when found, while keeping package publishing disabled.
- Remove concrete non-strategy archive blockers from the benchmark package path
  when found, while keeping package publishing disabled.
- Make the release-plan evidence show the full modular workspace dependency
  edge graph, including private packages that are not currently publishable and
  the approved modular-plus-compatibility strategy.
- Make the deployment-chain audit require strict Dart package readiness once
  the first publishable slice is unblocked.

## Non-Goals

- Publishing to pub.dev.
- Claiming package names or configuring publisher ownership.
- Renaming packages or replacing the legacy public `connectanum` package beyond
  the approved compatibility wrapper/facade strategy.
- Making router, auth-server, or benchmark packages public in this slice.
- Rewriting local router package dependencies to hosted package constraints
  before their package release slices are approved.

## Milestones

- [x] Confirm the strict package gate still identifies the private
  `connectanum_core` dependency as the release blocker.
- [x] Confirm current pub.dev package-name state for the legacy and modular package
  names.
- [x] Clear concrete pre-publish blockers for `connectanum_core` before
  enabling publishability.
- [x] Make the private `connectanum_router` archive clear its concrete
  changelog and false-secret fixture blockers while keeping it private.
- [x] Make the private `connectanum_auth_server` archive clear its concrete
  changelog blocker while keeping it private.
- [x] Make the private `connectanum_bench` archive clear its concrete changelog
  and false-secret fixture blockers while keeping it private.
- [x] Make `--show-release-plan` expose the full workspace dependency order for
  modular package publishing without changing package publishability.
- [x] Re-run local verification and clean package-copy package dry-runs.
- [x] Decide the package release strategy: publish modular packages in dependency
  order, keep using the legacy `connectanum` name for client compatibility, or
  provide a compatibility wrapper.
- [x] Make `connectanum_core` the first publishable modular archive after the
  strategy decision.
- [x] Make strict Dart package readiness succeed for the current publishable
  slice.
- [x] Harden router CLI consumer-smoke readiness after full verification exposed
  a startup timing false negative.
- [x] Make `connectanum_mcp` publishable after confirming its package dry-run
  has zero warnings and no private workspace dependency blockers.

## Verification

- `bin/test-fast`
- `bin/dart-package-publish-dry-run --strict-release-ready --show-release-plan`
- `bin/dart-package-publish-dry-run --include-private connectanum_core`
- `bin/dart-package-publish-dry-run --include-private connectanum_router`
- `bin/dart-package-publish-dry-run --include-private connectanum_auth_server`
- `bin/dart-package-publish-dry-run --include-private connectanum_bench`
- `bin/dart-package-publish-dry-run --include-private --show-release-plan connectanum_mcp`
- `bin/dart-package-publish-dry-run --strict-release-ready --show-release-plan connectanum_mcp`
- `bin/verify`
- Clean package-copy simulation: `git archive` the repo, overlay the new
  `connectanum_core` package metadata, then run
  `bin/dart-package-publish-dry-run --include-private connectanum_core`.
- Focused router CLI consumer package smoke after readiness wait hardening.

## Decision Log

- 2026-07-08: Promoted `connectanum_mcp` into the current publishable modular
  slice after `bin/dart-package-publish-dry-run --include-private
  --show-release-plan connectanum_mcp` reported zero warnings and no private
  workspace dependency blockers. The package keeps hosted constraints on
  `connectanum_core` and `connectanum_client`, both already publishable in the
  approved modular dependency order. Focused release-tooling tests, strict MCP
  package dry-run, full local verification, and hosted evidence are pending for
  this slice. Focused release-tooling tests, audit-tool tests, MCP package
  analysis, public-artifact reference scanning, shell syntax checks, and
  whitespace checks passed before commit; the clean strict MCP package dry-run
  and full `bin/verify` are the post-commit handoff gates because pub correctly
  warns while the package pubspec is modified but uncommitted.
- 2026-07-08: Approved the package strategy as modular packages published in
  dependency order with the legacy public `connectanum` package kept as the
  client-facing compatibility wrapper/facade. `connectanum_core` is now the
  first publishable modular archive, so the current strict publishable slice
  `connectanum_core` + `connectanum_client` has no private workspace dependency
  blockers. The release-plan output now prints the approved strategy, and the
  deployment-chain audit no longer accepts the old first-RC pub.dev deferral
  once strict Dart package readiness is attainable. Baseline `bin/test-fast`,
  focused release-tooling/audit tests, strict client dry-run, clean archive
  simulation for `connectanum_core`, focused router CLI consumer package smoke,
  and full local `bin/verify` passed on 2026-07-08. Hosted CI `28929989284`,
  Dart Package Publish Dry Run `28929989365`, and WAMP Profile Benchmarks
  `28929989280` passed at `c363c64`. The clean deployment-chain audit passed
  with CI/log, Dart package dry-run, WAMP benchmark, workflow visibility, and
  router-package requirements; the strict audit still fails only for the known
  unprotected `add-router` branch policy gap.
- 2026-07-07: Hardened release-plan evidence without changing package
  publishability. `bin/dart-package-publish-dry-run --show-release-plan` now
  inventories dependency edges for private workspace packages as well as
  currently publishable packages, so the modular publishing order is visible
  across `connectanum_core`, `connectanum_client`, `connectanum_mcp`,
  `connectanum_router`, `connectanum_auth_server`, and `connectanum_bench`.
  `publish_to: none` and dependency sources remain unchanged. Baseline
  `bin/test-fast`, focused `bash -n bin/dart-package-publish-dry-run`,
  focused `python3 -m unittest tool.test_dart_package_publish_dry_run`,
  `bin/dart-package-publish-dry-run --include-private --show-release-plan
  connectanum_mcp`, and the expected-failing strict
  `bin/dart-package-publish-dry-run --strict-release-ready --show-release-plan
  connectanum_client` passed with zero package warnings; the strict command
  still exits non-zero only for the explicit package strategy decision. Full
  local `bin/verify` passed after the change. Hosted CI `28899161182` and Dart
  Package Publish Dry Run `28899161241` passed at `4c9b903`; the clean
  deployment-chain audit passed with WAMP Profile Benchmarks `28895963701`
  from `13af852` still clean and relevant because no WAMP profile
  benchmark-sensitive paths changed. The strict audit still fails only for the
  known unprotected `add-router` branch policy gap.
- 2026-07-07: Removed concrete benchmark package archive blockers without
  changing package publishing strategy. `connectanum_bench` now has a package
  changelog and a scoped `false_secrets` entry for the inline private-key test
  fixture in `test/wamp_transport_targets_test.dart`.
  `bin/dart-package-publish-dry-run --include-private connectanum_bench` no
  longer reports missing-changelog or false-secret errors; it still exits
  non-zero for the strategy-bound local workspace dependencies on
  `connectanum_router`, `connectanum_core`, `connectanum_client`, and
  `connectanum_auth_server`. Baseline `bin/test-fast`, focused
  `python3 -m unittest tool.test_dart_package_publish_dry_run`,
  `python3 tool/check_public_artifact_references.py`, `git diff --check`, and
  full local `bin/verify` passed. Hosted CI `28895964175`, Dart Package
  Publish Dry Run `28895963910`, and WAMP Profile Benchmarks `28895963701`
  passed at `13af852`; the clean deployment-chain audit passed, and the strict
  audit still fails only for the known unprotected `add-router` branch policy
  gap. The package release strategy milestone remains open.
- 2026-07-07: Removed the concrete auth-server package archive blocker without
  changing package publishing strategy. `connectanum_auth_server` now has a
  package changelog. `bin/dart-package-publish-dry-run --include-private
  connectanum_auth_server` no longer reports a missing-changelog error; it
  still exits non-zero for the strategy-bound local workspace dependencies on
  `connectanum_router` and `connectanum_core`. Baseline `bin/test-fast`,
  focused `python3 -m unittest tool.test_dart_package_publish_dry_run`, and
  full local `bin/verify` passed. Hosted CI `28893021047` and Dart Package
  Publish Dry Run `28893020916` passed at `f99ad60`; the clean
  deployment-chain audit passed with WAMP Profile Benchmarks `28890098533`
  from `b226a08` still clean and relevant because no WAMP profile
  benchmark-sensitive paths changed. The strict audit still fails only for the
  known unprotected `add-router` branch policy gap.
- 2026-07-07: Removed concrete router package archive blockers without changing
  package publishing strategy. `connectanum_router` now has a package changelog
  and scoped `false_secrets` entries for checked-in test TLS key fixtures and
  inline test key snippets. `bin/dart-package-publish-dry-run --include-private
  connectanum_router` no longer reports missing-changelog or false-secret
  errors; it still exits non-zero for the strategy-bound local workspace
  dependencies on `connectanum_core`, `connectanum_client`, and
  `connectanum_mcp`. Baseline `bin/test-fast` and focused
  `python3 -m unittest tool.test_dart_package_publish_dry_run` passed. Full
  local `bin/verify` passed after the change. Hosted CI, Dart Package Publish
  Dry Run, WAMP Profile Benchmarks, and the clean deployment-chain audit passed
  at `b226a08`; the strict audit still fails only for the known unprotected
  `add-router` branch policy gap.
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

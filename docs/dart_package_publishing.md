# Dart Package Publishing Readiness

This document records the current package-publishing state for the
Connectanum Dart workspace. It is intentionally separate from the native FFI
release flow because pub.dev publishing has its own ownership, package-name,
and version-sequencing decisions.

## Current Status

- The approved strategy is to publish the modular package graph in dependency
  order while keeping the legacy public `connectanum` package as the
  client-facing compatibility wrapper/facade.
- `connectanum_core`, `connectanum_client`, `connectanum_mcp`,
  `connectanum_router`, `connectanum_auth_server`, and `connectanum_bench` are
  all configured as publishable archives. None of these workspace packages sets
  `publish_to: none`.
- Every package now carries the repo MIT license in its package root so future
  package archives satisfy pub.dev's mandatory license check.
- Every package pubspec now points to the GitHub repository and issue tracker
  so package metadata is readable when a package becomes public.
- `bin/dart-package-publish-dry-run` is the canonical non-mutating local check
  for package archive readiness. It discovers publishable workspace packages,
  skips private packages by default, and runs `dart pub publish --dry-run` for
  each publishable package.
- The dry-run command now also requires each publishable package dry-run to
  report `Package has 0 warnings`; warning-bearing package archives fail the
  release-evidence gate even when pub's process exit status is successful.
- The same tool reports release-readiness blockers when a publishable package
  depends on a private workspace package. Its default mode keeps archive
  validation non-mutating and green, while `--strict-release-ready` exits
  non-zero if the package graph regresses.
- `--show-release-plan` prints the full workspace package inventory, the
  dependency order, and operator decisions needed for a real publish without
  changing package publishability.
- `.github/workflows/dart-package-publish.yml` runs
  `bin/dart-package-publish-dry-run --strict-release-ready --show-release-plan`
  on GitHub for any package archive-input change under `packages/**`, the
  dry-run tool, this readiness document, and the workflow itself. It can also
  be started manually with `workflow_dispatch`.
- As of 2026-07-07, pub.dev exposes the legacy public `connectanum` package at
  `2.2.7`. The modular package names `connectanum_client`, `connectanum_core`,
  `connectanum_router`, `connectanum_mcp`, and `connectanum_auth_server`
  returned `404` from the pub.dev package API. That makes package naming and
  publisher ownership an explicit migration decision, not just a metadata
  cleanup task.

## Latest Evidence

As of 2026-07-08:

- `bin/dart-package-publish-dry-run --strict-release-ready --show-release-plan`
  validates all six publishable workspace packages with `Package has 0
  warnings` and reports no private workspace dependency blockers.
- The release-plan dependency order is
  `connectanum_core -> connectanum_client -> connectanum_mcp ->
  connectanum_router -> connectanum_auth_server -> connectanum_bench` where
  each edge exists in the package graph.
- Clean scoped strict dry-runs passed for the `connectanum_mcp`,
  `connectanum_router`, `connectanum_auth_server`, and `connectanum_bench`
  package-release slices after their hosted runtime constraints were applied.
- Full local `bin/verify` passed after the bench package became publishable at
  commit `4ef668b`.
- Hosted GitHub evidence for commit `4ef668b` is clean: CI `28944706690`,
  Dart Package Publish Dry Run `28944706698`, and WAMP Profile Benchmarks
  `28944706579` passed.
- The clean deployment-chain audit passed with CI/log, Dart package dry-run,
  WAMP benchmark, workflow visibility, and router-package requirements at
  `4ef668b`. Strict audit still fails only for the known operator-owned
  `add-router` branch-protection gap.

## Release Sequence

Do not publish any Dart package from the autonomous loop without an explicit
operator/product decision for the package names, versions, and ownership.

When that decision exists, use this sequence:

1. Confirm the target package names exist or are claimable on pub.dev.
2. For any modular package name that is not already published, create the
   first version manually with `dart pub publish`; pub.dev automated publishing
   only supports existing packages. See the official Dart automated publishing
   guide: <https://dart.dev/tools/pub/automated-publishing>.
3. If GitHub automated publishing will be used for later versions, configure it
   on pub.dev for the package, repository, tag pattern, and workflow before
   relying on CI. Pub.dev accepts GitHub Actions automated publishes only from
   tag-triggered workflows.
4. Run `dart pub publish --dry-run` in each package that will be published.
5. Run `bin/dart-package-publish-dry-run --strict-release-ready
   --show-release-plan` to confirm the dependency order, zero-warning archives,
   and remaining operator decisions.
6. Publish packages in dependency order, starting with `connectanum_core`.
7. Record exact package versions and pub.dev URLs in `docs/project_state.md`
   and the active execution plan.

## Current Blockers

- No code-owned archive-readiness or private workspace dependency blockers
  remain for the modular package graph.
- The canonical Dart package release versions have not been chosen for the
  modular workspace packages.
- Package ownership and publisher configuration on pub.dev have not been
  confirmed in checked-in evidence.
- First-version publication for any new modular package name still requires an
  explicit manual `dart pub publish` by an authorized uploader/publisher admin
  before automated publishing can be used for later versions.
- The legacy package name `connectanum` is already public, while the modular
  package names were not published at the last checked API probe. A release
  decision must still choose the exact migration sequence for modular packages
  and the compatibility wrapper/facade.

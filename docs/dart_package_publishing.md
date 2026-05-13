# Dart Package Publishing Readiness

This document records the current package-publishing state for the
Connectanum Dart workspace. It is intentionally separate from the native FFI
release flow because pub.dev publishing has its own ownership, package-name,
and version-sequencing decisions.

## Current Status

- `connectanum_client` is the only workspace package currently configured for
  public publishing. It does not set `publish_to: none`.
- `connectanum_core`, `connectanum_router`, `connectanum_mcp`,
  `connectanum_auth_server`, and `connectanum_bench` are still private
  workspace packages because their pubspecs set `publish_to: none`.
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
  non-zero once the operator wants the package release plan enforced.
- `--show-release-plan` prints the full private workspace package inventory,
  the subset that blocks currently publishable packages, the dependency order,
  and operator decisions needed for a real publish without changing package
  publishability.
- `.github/workflows/dart-package-publish.yml` runs the same dry-run on GitHub
  for any package archive-input change under `packages/**`, the dry-run tool,
  this readiness document, and the workflow itself. It can also be started
  manually with `workflow_dispatch`.

## Latest Evidence

As of 2026-05-02:

- `bin/dart-package-publish-dry-run --show-release-plan` skips the private
  workspace packages and validates `packages/connectanum_client`.
- The underlying `dart pub publish --dry-run` for `connectanum_client` passes
  with `Package has 0 warnings`.
- The root dry-run command enforces that zero-warning result and reports
  `All Dart package publish dry-runs reported zero warnings`.
- The default dry-run reports that `connectanum_client` depends on private
  workspace package `connectanum_core`.
- `bin/dart-package-publish-dry-run --strict-release-ready` intentionally
  fails on that blocker until `connectanum_core` is published first or the
  client package is restructured to avoid the unpublished hosted dependency.
- `bin/dart-package-publish-dry-run --show-release-plan` reports the current
  public-release chain as `connectanum_core 0.1.0` before
  `connectanum_client 2.2.6`.
- The same release-plan output now lists every private workspace package
  separately from blocker packages, so non-blocking private packages such as
  `connectanum_mcp`, `connectanum_router`, `connectanum_auth_server`, and
  `connectanum_bench` stay visible in release-readiness evidence without being
  treated as approved public packages.
- The same dry-run is only local package validation. The pub.dev API returned
  `404` for both `connectanum_client` and `connectanum_core` on 2026-05-02, so
  a real publish still needs package ownership and publish-order decisions.
- `connectanum_client` depends on `connectanum_core: ^0.1.0`. A real
  `connectanum_client` publish should not be attempted until either
  `connectanum_core` is intentionally published first or the client package is
  restructured to avoid an unpublished public dependency.
- GitHub `Dart Package Publish Dry Run` run `25257170706` passed on
  `f31b025` after the MCP tool-result content block change under `packages/**`.
  It covers the current package-publishing inputs and confirms the broadened
  package path filters are exercising package/test changes.

## Release Sequence

Do not publish any Dart package from the autonomous loop without an explicit
operator/product decision for the package names, versions, and ownership.

When that decision exists, use this sequence:

1. Confirm the target package names exist or are claimable on pub.dev.
2. Decide whether `connectanum_core` is public API. If yes, remove
   `publish_to: none` only as part of an explicit release slice and publish it
   before packages that depend on it.
3. Run `dart pub publish --dry-run` in each package that will be published.
4. Run `bin/dart-package-publish-dry-run --show-release-plan` to confirm the
   dependency order and remaining operator decisions.
5. Run `bin/dart-package-publish-dry-run --strict-release-ready` and resolve
   any private workspace dependency blockers before publishing.
6. Publish packages in dependency order, starting with `connectanum_core`.
7. Record exact package versions and pub.dev URLs in `docs/project_state.md`
   and the active execution plan.

## Current Blockers

- `connectanum_core` is still private, but `connectanum_client` declares it as
  a public hosted dependency.
- The canonical Dart package release versions have not been chosen for the
  modular workspace packages.
- Package ownership on pub.dev has not been confirmed in checked-in evidence.

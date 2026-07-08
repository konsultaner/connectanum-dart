# Exec Plan: Pub.dev Automated Publish Workflows

Status: complete
Owner: Codex
Created: 2026-07-08
Last updated: 2026-07-08

## Problem

The Dart package graph is archive-ready, but a real pub.dev release still needs
an operator-controlled publication path. The default pub.dev path for later
package versions is tag-triggered GitHub Actions publishing with OIDC, not
long-lived tokens. The repository needs checked-in workflow scaffolding and
validation so an operator can enable automated publishing after the manual first
publication of any new package names.

## Scope

- Add dormant, per-package GitHub Actions workflows for the publishable modular
  packages and the legacy `connectanum` compatibility facade.
- Use package-specific tags shaped as `<package>-v<pubspec-version>`.
- Validate the package tag and package archive before calling the reusable Dart
  pub.dev publish workflow.
- Keep the flow non-mutating unless a matching package tag is pushed and the
  corresponding pub.dev package has automated publishing enabled.
- Update release-readiness docs and tests to pin the workflow contract.

## Non-Goals

- Do not publish packages to pub.dev.
- Do not create or push package version tags.
- Do not choose package ownership, publisher, or canonical release versions.
- Do not change package versions.

## Verification

- `bin/test-fast` before edits.
- `python3 -m unittest tool.test_dart_package_publish_dry_run`
- `bash -n bin/validate-dart-package-publish-tag bin/dart-package-publish-dry-run`
- `ruby -e "require 'yaml'; Dir['.github/workflows/*.yml'].sort.each { |path| YAML.load_file(path); puts path }"`
- `python3 tool/check_public_artifact_references.py`
- `git diff --check`
- `bin/verify`

## Handoff

Complete. The implementation adds dormant per-package pub.dev publish workflows
for all publishable workspace packages, the package/tag validator,
release-readiness documentation, and workflow contract tests. `bin/test-fast`
passed before edits; focused unit, shell, workflow-YAML, public-artifact, diff,
validator, and strict dry-run checks passed after the change; full local
`bin/verify` passed before handoff. Real pub.dev publishing remains
operator-gated until package ownership, manual first-version publication,
automated publishing setup, tag pushes, and optional GitHub environment
approvals are configured.

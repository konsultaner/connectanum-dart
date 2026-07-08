# Exec Plan: Strict Dart Package Workflow

Status: complete
Owner: Codex
Created: 2026-07-08
Last updated: 2026-07-08

## Problem

The full modular Dart package graph is now publishable, but the hosted package
workflow and release-plan wording still reflected the earlier staged/private
package state. That leaves CI evidence weaker than the current package graph
allows and keeps public release docs stale.

## Scope

- Make the existing GitHub Dart package workflow run the strict release-ready
  dry-run across the full publishable graph.
- Remove stale release-plan messaging that implies remaining private package
  slices when none are present.
- Refresh the package-publishing readiness doc for the all-publishable modular
  graph while keeping real pub.dev publishing blocked on operator approval,
  package ownership, first-version publication, and version choices.
- Do not publish to pub.dev, create tags, configure pub.dev automated
  publishing, or claim package names.

## Milestones

- [x] Run baseline `bin/test-fast`.
- [x] Update workflow/tooling/test/docs for strict full-graph readiness.
- [x] Run focused release-tooling checks.
- [x] Run full `bin/verify`.
- [x] Prepare the code/config/docs bundle for commit. Hosted package dry-run/CI
  evidence should be inspected after push and reported in handoff rather than
  committed as a docs-only follow-up.

## Verification

- `bin/test-fast`
- `python3 -m unittest tool.test_dart_package_publish_dry_run`
- `bash -n bin/dart-package-publish-dry-run`
- `ruby -e "require 'yaml'; YAML.load_file('.github/workflows/dart-package-publish.yml'); puts 'yaml_ok'"`
- `bin/dart-package-publish-dry-run --strict-release-ready --show-release-plan`
- `python3 tool/check_public_artifact_references.py`
- `git diff --check`
- `bin/verify`

## Decision Log

- 2026-07-08: Baseline `bin/test-fast` passed before the workflow/readiness
  edits. Official Dart pub.dev guidance keeps this slice non-mutating: GitHub
  automated publishing is tag-triggered and only works for existing packages,
  so the code-owned next step is strict dry-run evidence rather than a real
  publish workflow.
- 2026-07-08: Focused release-tooling checks passed after the edits:
  `python3 -m unittest tool.test_dart_package_publish_dry_run`,
  `bash -n bin/dart-package-publish-dry-run`,
  `ruby -e "require 'yaml'; YAML.load_file('.github/workflows/dart-package-publish.yml'); puts 'yaml_ok'"`,
  `python3 tool/check_public_artifact_references.py`, `git diff --check`, and
  `bin/dart-package-publish-dry-run --strict-release-ready --show-release-plan`.
- 2026-07-08: Full local `bin/verify` passed after the strict workflow/readiness
  implementation.

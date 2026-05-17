# Dart Package Dry-Run Regression

Status: implemented with clean local verification; commit/push and hosted
evidence are pending.

## Goal

Pin the release-order behavior that keeps pub.dev publishing outside the first
GitHub RC while still making the dry-run and audit output repeatable. The
default Dart package dry-run must continue to pass when publishable packages
have known private workspace dependencies, while strict release-ready mode must
fail until the package ownership/version/release-order decision is made.

## Plan

- Add a fast regression test for `bin/dart-package-publish-dry-run` using a
  temporary minimal workspace and fake `dart` executable.
- Assert default `--show-release-plan` mode reports the private dependency
  blocker and release order without failing the archive dry-run gate.
- Assert `--strict-release-ready --show-release-plan` fails on the same private
  dependency blocker.
- Run the regression in both `bin/test-fast` and `bin/test-all`.
- Bundle the pending hosted-evidence project-state bookkeeping from the
  previous deployment audit slice with this implementation commit.

## Verification

- `bin/test-fast`: passed before edits on 2026-05-17.
- `python3 tool/test_dart_package_publish_dry_run.py`: passed on 2026-05-17.
- `bin/test-fast`: passed after edits on 2026-05-17.
- `git diff --check`: passed.
- Private-name/local-path scan on touched public docs/tooling paths: passed.
- `bin/verify`: passed on 2026-05-17.

## Remaining

- Commit and push the implementation plus state updates.
- Collect required hosted CI/package dry-run evidence after push.

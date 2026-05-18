# Dart Package Dry-Run Regression

Status: implemented with clean local and hosted verification. No further
implementation remains for this slice.

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
- Commit `8777a82`: pushed to GitHub on
  `codex/post-rc-production-readiness`.
- Hosted push CI #25989952453: passed.
- Hosted PR CI #25989953492: passed.
- Hosted Dart Package Publish Dry Run #25989953493: passed.
- Strict deployment-chain audit with latest CI/logs, package dry-run, workflow
  visibility, GHCR visibility, WAMP benchmark relevance, native artifact
  relevance, router image relevance, and RC-readiness reporting: passed for the
  enforced gates. RC readiness remains blocked by PR #79 review/merge, fresh RC
  tag/release approval, and tag-matched Native Artifacts and Router Image
  evidence; pub.dev publishing remains intentionally deferred.

## Remaining

- Complete PR #79 review/merge and operator RC-tag controls before cutting the
  next RC from the promoted release branch.

# Router Image Node 24 Actions

Status: complete

## Goal

Keep the Router Image deployment chain warning-clean by removing the future
Node.js runtime deprecation annotation emitted by Docker setup action `v3`.

## Scope

- In scope: update Router Image workflow setup actions to the current Docker
  action major that declares Node 24 support, then validate the workflow and
  dry-run audit path.
- Out of scope: changing image tags, publishing images, creating RC tags, or
  changing Docker build/publish semantics.

## Implementation

- `.github/workflows/router-image.yml` now uses
  `docker/setup-qemu-action@v4` and `docker/setup-buildx-action@v4`.
- GitHub release metadata reports `v4.0.0` as the latest release for both
  actions, and both `action.yml` files declare `runs.using: node24`.
- The workflow also configures Git's default initial branch before checkout, so
  the dry-run log does not include the checkout-time `git init` branch-name
  warning hint.

## Verification

- `bin/test-fast` passed before edits.
- `ruby -e "require 'yaml'; YAML.load_file('.github/workflows/router-image.yml')"`
  passed.
- `git diff --check` passed.
- `bin/verify` passed on 2026-05-13.
- Hosted CI #25824593749 passed on `codex/post-rc-production-readiness` at
  `ed08c3e` after the action-major upgrade.
- Hosted Router Image dry-run #25824604845 passed at `ed08c3e`, but its log
  still contained Git's checkout-time branch-name warning hint.
- Follow-up hosted CI #25825256743 passed at `ae9ff88` after the hint
  suppression.
- Follow-up hosted Router Image dry-run #25825262531 passed at `ae9ff88` in
  3m1s, and its log had no warning/deprecation matches.
- The strict deployment-chain audit passed with clean latest CI/logs, relevant
  Native Artifacts dry-run evidence, relevant Router Image dry-run evidence,
  and router package visibility requirements enabled.
- PR #79 was opened from `codex/post-rc-production-readiness` into `master`
  and marked ready for review; its PR-triggered `Fast Checks` and
  `Full Verify` passed in run #25825933313 at `ae9ff88`, and its PR-triggered
  `Publish Dry Run` passed in run #25825933310.
- After installing the GitHub CLI in the local automation environment, the
  strict deployment-chain audit passed with full hosted log access for
  PR-triggered CI #25825933313, clean CI logs, relevant Dart package dry-run,
  relevant Native Artifacts dry-run, relevant Router Image dry-run, and router
  package visibility requirements enabled.
- GitHub reports PR #79 as mergeable, with `REVIEW_REQUIRED` as the remaining
  branch-protection gate.
- Manual WAMP Profile Benchmarks run #25827390502 passed on the PR head
  `ae9ff88`; `Linux WAMP profile gates` completed in 8m11s and uploaded WAMP
  profile artifacts.

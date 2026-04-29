# GitHub Deployment Chain

This repository uses GitHub Actions as the visible hosted deployment signal for
the `add-router` branch while the GitHub deployment chain is being hardened.
This page records the current repository controls and the evidence that should
exist before treating a release path as production-ready.

## Repeatable Audit

Run:

```sh
bin/audit-github-deployment-chain --branch master
bin/audit-github-deployment-chain --branch add-router
```

The audit is read-only. It uses the GitHub CLI and prints repository metadata,
branch protection, repository rulesets, active workflows, checked-in workflow
visibility, router container package visibility, and recent branch runs. If
`gh` is not on `PATH`, set `GH_BIN` to the executable path.

Use the clean-CI gate before treating a pushed branch head as verified:

```sh
bin/audit-github-deployment-chain \
  --branch add-router \
  --require-clean-latest-ci \
  --require-clean-latest-ci-logs
```

Those modes exit non-zero when the latest `CI` run is missing `Fast Checks` or
`Full Verify`, has unexpected jobs, has skipped jobs, has pending/failed jobs,
or when the hosted logs contain high-signal warning, deprecation, skipped-test,
rawsocket reset, or connection-noise patterns.

Use log-scan mode without failing the audit when manually triaging a run:

```sh
bin/audit-github-deployment-chain --branch add-router --scan-latest-ci-logs
```

The log scan intentionally avoids broad `error` and `failed` matching because
passing test names and Rust summaries currently include benign strings such as
`BCRYPT check password failed` and `0 failed`. Job status is the authoritative
source for real failed work.

Use the router package gate before treating the router image release path as
ready:

```sh
bin/audit-github-deployment-chain --branch add-router --require-router-package
```

That mode is also read-only. It intentionally exits non-zero until
`ghcr.io/konsultaner/connectanum-router` is visible through the GitHub Packages
API after the router image workflow is promoted and validated.

Use the workflow visibility gate before treating checked-in workflows as
available on GitHub Actions:

```sh
bin/audit-github-deployment-chain --branch add-router --require-workflows-visible
```

That mode exits non-zero while checked-in workflows, currently
`.github/workflows/router-image.yml`, are not discoverable through the GitHub
Actions API. It is read-only and does not promote workflows to the default
branch.

Use strict mode when the repository is ready for the branch-protection gap to
be enforced by automation:

```sh
bin/audit-github-deployment-chain --branch master --strict
```

Use the operator plan mode to print the exact required-status-check payload
without changing repository policy:

```sh
bin/audit-github-deployment-chain --branch master --show-required-checks-plan
```

## Current GitHub Controls

Snapshot date: 2026-04-28.

- Repository: `konsultaner/connectanum-dart`
- Visibility: public
- Default branch: `master`
- Active development branch: `add-router`
- Repository rulesets: none
- Auto-merge: disabled
- Delete branch on merge: disabled

`master` is protected. The current protection requires one approving review
from a code owner and disallows force pushes and branch deletion.

The current gap is required status checks: `master` has no required status
checks configured. A clean release branch should require at least:

- `Fast Checks`
- `Full Verify`

The current workflow visibility gap is router image publishing:
`.github/workflows/router-image.yml` exists on `add-router`, but GitHub does
not expose it through the Actions workflow API because it is not on the default
branch. `gh workflow view router-image.yml` currently returns `404`, and the
GHCR package `ghcr.io/konsultaner/connectanum-router` is not visible through
the GitHub Packages API. Public docs should therefore describe the router image
as staged until the workflow and package are validated. Manual router image
workflow dispatches are being kept dry-run by default until that promotion path
is explicitly validated.

`add-router` is not protected. That is acceptable for the active development
branch only while every pushed slice is watched manually and recorded in
`docs/project_state.md`.

Do not change branch protection silently from an autonomous continuation. Adding
or changing required checks affects merge policy and should be treated as an
operator decision. Once approved, keep the required checks minimal and stable;
path-filtered benchmark workflows should stay release evidence unless GitHub
rules are adjusted to avoid blocking unrelated changes.

## Release Evidence Policy

A deployment-chain slice is considered clean only when all relevant evidence is
available:

- Local `bin/test-fast` before substantial changes.
- Local `bin/verify` before handoff for code, workflow, or release behavior
  changes.
- Hosted GitHub `CI` success for the pushed head.
- Read-only clean-CI audit for the pushed head:
  `bin/audit-github-deployment-chain --branch add-router --require-clean-latest-ci --require-clean-latest-ci-logs`
  should report no skipped, pending, failed, missing, or unexpected `CI` jobs,
  and no high-signal warning/deprecation/skipped-test/reset/connection-noise
  log matches.
- Additional hosted workflow evidence when the slice changes release behavior:
  native artifact matrix, release dry-run, validation prerelease, WAMP profile
  benchmark gate, kTLS validation, or diagnostics as appropriate.
- Run IDs and any remaining blockers recorded in `docs/project_state.md` and
  the active execution plan.

Expected benign log matches outside the audit pattern must be called out
explicitly. Current known benign strings include passing test names such as
`BCRYPT check password failed` and Rust result summaries containing `0 failed`.

## Current Evidence

For the latest branch-head status, run the clean-CI audit command above. The
items below are pinned deployment-chain checkpoints from 2026-04-29, not a
replacement for the live audit:

- `add-router` commit `3db2bbe` passed GitHub `CI` run `25089948391`.
  `Fast Checks` and `Full Verify` completed successfully, and the clean-CI
  audit reported no skipped, pending, failed, missing, or unexpected `CI` jobs.
- Hosted log scanning for `25089948391` found no real warnings, deprecations,
  rawsocket reset noise, timeouts, cancellations, or errors. The only matches
  were expected benign strings: a passing bcrypt negative-test name and Rust
  `0 failed` summaries.
- `a3ae4a3` added the branch-protection operator plan. The audit now prints
  the required-status-check payload for `Fast Checks` and `Full Verify`
  without mutating GitHub repository policy.
- `1769982` added the clean-latest-CI audit gate. The main `CI` workflow now
  contains only `Fast Checks` and `Full Verify`.
- `5441730` removed the duplicate manual-only WAMP profile job from main `CI`;
  canonical WAMP profile gates remain in the dedicated
  `WAMP Profile Benchmarks` workflow.
- `ee32ad3` added Dart package release-readiness blocker reporting. GitHub
  run `25084695572` passed and surfaced the current
  `connectanum_client` -> private `connectanum_core` blocker without
  publishing to pub.dev.
- `d9cbd81` added the dedicated non-mutating Dart package publish dry-run
  workflow.
- `be29fe6` added the router image dry-run/manual publish-approval gate before
  default-branch workflow promotion.
- `1b95c9d` passed the dedicated `WAMP Profile Benchmarks` run
  `25071505445`.

The next deployment-chain improvement should either apply the approved branch
protection settings, promote and validate the router image workflow/package, or
continue tightening release evidence around GitHub Releases and Dart package
publishing without publishing stable artifacts.

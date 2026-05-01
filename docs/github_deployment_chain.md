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

Use the dedicated Dart package evidence gate before treating package metadata
or package release inputs as validated:

```sh
bin/audit-github-deployment-chain \
  --branch add-router \
  --require-clean-dart-package-publish-dry-run
```

That gate checks the latest `Dart Package Publish Dry Run` workflow, verifies
the expected `Publish Dry Run` job completed successfully, and confirms the
checked-out head has not changed any package-publish-sensitive inputs since
that workflow run. Docs-only checkpoints can therefore stay valid without
rerunning package archive validation, while package metadata or pubspec changes
must be covered by a fresh dedicated dry-run.

Use the dedicated native release evidence gate before treating native FFI
artifacts or release-preview inputs as validated:

```sh
bin/audit-github-deployment-chain \
  --branch add-router \
  --require-clean-native-release-dry-run
```

That gate checks the latest manual `Native Artifacts` dry-run, verifies the
Linux, macOS, and Windows matrix plus `Publish GitHub Release` preview job,
confirms the `native-release-preview` artifact was uploaded, confirms the
dry-run tag did not create a GitHub Release, and fails when checked-out native
release-sensitive inputs changed after that run.

Use the release-candidate readiness view when deciding whether the current
branch head is feature-wise ready to tag as an RC:

```sh
bin/audit-github-deployment-chain --branch add-router --show-rc-readiness
```

Use the strict RC gate only when the remaining operator-owned blockers are
expected to be resolved:

```sh
bin/audit-github-deployment-chain --branch add-router --require-rc-ready
```

The RC view is read-only. It combines clean CI, clean hosted logs, branch
protection, workflow visibility, router package visibility, hosted Dart package
publish dry-run evidence, hosted native release dry-run evidence, RC
tag/prerelease evidence, and strict Dart package readiness. When Dart package
readiness is the blocker, the audit prints the package release-order plan so
the current `connectanum_core` -> `connectanum_client` dependency decision is
visible in the same output.

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

## RC Promotion Checklist

Before calling a branch head RC-ready, keep the order boring and observable:

1. Confirm the candidate branch head has clean hosted `CI` and clean hosted
   logs with `--require-clean-latest-ci --require-clean-latest-ci-logs`.
2. Confirm dedicated package/release evidence with
   `--require-clean-dart-package-publish-dry-run` and
   `--require-clean-native-release-dry-run`.
3. Apply or confirm branch protection on `master` only after operator approval.
   The minimal required checks are `Fast Checks` and `Full Verify`.
4. Promote `.github/workflows/router-image.yml` through the default branch,
   run a manual dry-run, then publish and validate
   `ghcr.io/konsultaner/connectanum-router` only after the image tag and
   publish approval are explicit.
5. Choose the RC tag and prerelease naming, then create the GitHub prerelease
   only after the native release dry-run and package release-order evidence are
   still current.
6. Decide the Dart package release order and ownership before any pub.dev
   publish. The current dependency order is `connectanum_core` before
   `connectanum_client`.

## Current GitHub Controls

Snapshot date: 2026-04-30.

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
is explicitly validated. Router image publish builds request max-level
provenance and SBOM attestations; dry-run cache-only builds keep image
attestations disabled because there is no registry image to attach them to.
Manual dry-runs upload `router-image-preview/router-image-metadata.md` so the
resolved tags, labels, publish mode, and attestation settings are available as
a downloadable artifact as well as an Actions step summary.

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
- Dedicated Dart package publish dry-run evidence for package-release inputs:
  `bin/audit-github-deployment-chain --branch add-router --require-clean-dart-package-publish-dry-run`
  should report a successful `Publish Dry Run` job that covers the checked-out
  package-publishing inputs.
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
items below are pinned deployment-chain checkpoints, not a replacement for the
live audit:

- `add-router` deployment-audit checkpoint `425385d` passed GitHub `CI` run
  `25195627202`: `Fast Checks` completed in 5m40s and `Full Verify` completed
  in 6m50s.
- `WAMP Profile Benchmarks` run `25195627213` passed on `425385d` in 8m00s,
  covering the WAMP profile gate after the native worker readiness test fix.
- The clean deployment-chain audit passed for `425385d` on 2026-05-01 with
  `--require-clean-latest-ci`, `--require-clean-latest-ci-logs`,
  `--require-clean-dart-package-publish-dry-run`, and
  `--require-clean-native-release-dry-run`.
- Hosted log scanning for `25195627202` found no warning, deprecation,
  skipped-test, reset, connection-noise, panic, or failure patterns.
- GitHub `Dart Package Publish Dry Run` run `25195627219` passed on
  `425385d` and covers the native WAMP worker test change under `packages/**`.
- Manual `Native Artifacts` dry-run `25192553399` passed on `4267e7a`, covered
  Linux x64, Linux arm64, macOS Apple Silicon, macOS Intel, Windows x64, and
  the dry-run `Publish GitHub Release` job, uploaded `native-release-preview`,
  accepted `ct-ffi-v2026.04.30-dry-run.4267e7a`, and did not create or update a
  GitHub Release. It remains relevant for `425385d` because no
  native-release-sensitive inputs changed after that run.

- `add-router` deployment-audit checkpoint `1b5686f` passed GitHub `CI` run
  `25187265086`: `Fast Checks` completed in 5m36s and `Full Verify`
  completed in 8m01s.
- The clean-CI audit passed for `1b5686f` with
  `--require-clean-latest-ci --require-clean-latest-ci-logs`; hosted CI logs
  had no high-signal warning, deprecation, skipped-test, panic, broken-pipe,
  reset, timeout, or connection-noise matches.
- GitHub `Dart Package Publish Dry Run` run `25187265107` passed on
  `1b5686f`; it covers the checked-out package-publishing inputs and keeps the
  current `connectanum_core` before `connectanum_client` release-order blocker
  visible without publishing to pub.dev.
- The branch-head deployment-chain audit passes the clean main `CI`, clean
  hosted `CI` log, and clean/relevant Dart package dry-run gates for
  `1b5686f`.
- Manual `Native Artifacts` dry-run `25166714340` remains clean and relevant
  for `1b5686f` because no native-release-sensitive paths changed after
  `7098c54`.
- `add-router` deployment-audit checkpoint `c8b6a13` passed GitHub `CI` run
  `25172656687`: `Fast Checks` completed in 5m37s and `Full Verify`
  completed in 8m10s.
- The clean-CI audit passed for `c8b6a13` with
  `--require-clean-latest-ci --require-clean-latest-ci-logs`; hosted CI logs
  had no high-signal warning, deprecation, skipped-test, panic, broken-pipe,
  reset, timeout, or connection-noise matches.
- `out/production` generated output is no longer tracked by Git; `/out/`
  remains ignored and `git ls-files out` returns zero tracked paths.
- GitHub `Dart Package Publish Dry Run` run `25170846455` passed on
  `a4818c8` and remains relevant for `c8b6a13` because no
  package-publish-sensitive inputs changed after that run.
- Manual `Native Artifacts` dry-run `25166714340` passed on `7098c54`,
  uploaded `native-release-preview`, accepted
  `ct-ffi-v2026.04.30-dry-run.7098c54`, and did not create a GitHub Release.
  It remains relevant for `c8b6a13` because no native-release-sensitive inputs
  changed after `7098c54`.
- The current audit gates pass for clean main `CI`, clean hosted `CI` logs,
  clean/relevant Dart package dry-run evidence, and clean/relevant native
  release dry-run evidence on the current branch head.
- `bin/audit-github-deployment-chain` falls back to the unfiltered branch run
  list when GitHub's workflow-filtered run list temporarily lags a freshly
  completed run, avoiding false negatives in deployment-chain evidence checks.
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

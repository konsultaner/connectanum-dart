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

Use strict mode when the repository is ready for the branch-protection gap to
be enforced by automation:

```sh
bin/audit-github-deployment-chain --branch master --strict
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
as staged until the workflow and package are validated.

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
- Hosted log scan with no real warnings, deprecations, unexpected skipped tests,
  rawsocket reset noise, timeouts, cancellations, or real errors.
- Additional hosted workflow evidence when the slice changes release behavior:
  native artifact matrix, release dry-run, validation prerelease, WAMP profile
  benchmark gate, kTLS validation, or diagnostics as appropriate.
- Run IDs and any remaining blockers recorded in `docs/project_state.md` and
  the active execution plan.

Expected benign log matches must be called out explicitly. Current known benign
matches include passing test names such as `BCRYPT check password failed` and
Rust result summaries containing `0 failed`.

## Current Evidence

The latest audited branch evidence on 2026-04-28:

- `add-router` commit `21a998d` passed GitHub `CI` run `25074424163`.
- `Fast Checks` and `Full Verify` completed successfully.
- `WAMP Profile Gates` in the main `CI` workflow were skipped because the run
  was not a manual `workflow_dispatch`; the dedicated `WAMP Profile Benchmarks`
  workflow remains the benchmark gate for relevant push paths and manual runs.
- Hosted log scanning found no real warnings, deprecations, rawsocket reset
  noise, timeouts, cancellations, or errors.
- `add-router` commit `1b95c9d` passed the dedicated `WAMP Profile Benchmarks`
  run `25071505445`.
- `be37ec4` added the read-only deployment-chain audit and passed GitHub `CI`
  run `25073711527`.

The next deployment-chain improvement should either apply the approved branch
protection settings, promote and validate the router image workflow/package, or
continue tightening release evidence around GitHub Releases and Dart package
publishing without publishing stable artifacts.

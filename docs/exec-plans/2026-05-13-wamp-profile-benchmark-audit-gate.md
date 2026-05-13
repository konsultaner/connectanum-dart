# WAMP Profile Benchmark Audit Gate

Status: in progress

## Goal

Make WAMP Profile Benchmarks a first-class GitHub deployment-chain audit gate
for RC readiness, matching the release plan instead of relying on manual PR
notes.

## Scope

- In scope: add read-only audit flags for WAMP Profile Benchmarks evidence,
  include the gate in `--show-rc-readiness` / `--require-rc-ready`, and ensure
  WAMP benchmark workflow triggering covers core serializer changes.
- Out of scope: changing benchmark budgets, scenario contents, or publishing an
  RC tag/release.

## Implementation

- `bin/audit-github-deployment-chain` now supports
  `--show-wamp-profile-benchmarks` and
  `--require-clean-wamp-profile-benchmarks`.
- `--require-rc-ready` now requires clean, relevant WAMP Profile Benchmarks
  evidence in addition to CI, logs, package dry-run, native release evidence,
  router image dry-run evidence, branch protection, workflow visibility, router
  package visibility, RC prerelease state, and the deferred pub.dev decision.
- `.github/workflows/wamp-profile-benchmarks.yml` now triggers on
  `packages/connectanum_core/**` changes because WAMP serializers and message
  behavior live there.

## Verification

- `bin/test-fast` passed before edits.
- `bash -n bin/audit-github-deployment-chain` passed.
- `bin/audit-github-deployment-chain --help` includes the new WAMP benchmark
  audit options.
- `ruby -e "require 'yaml'; YAML.load_file('.github/workflows/wamp-profile-benchmarks.yml')"`
  passed.
- `bin/audit-github-deployment-chain --branch codex/post-rc-production-readiness --run-limit 6 --show-wamp-profile-benchmarks`
  reports WAMP Profile Benchmarks run #25827390502 green at `ae9ff88` with a
  31-file artifact bundle.
- `bin/audit-github-deployment-chain --branch codex/post-rc-production-readiness --run-limit 6 --require-clean-wamp-profile-benchmarks`
  passed against the latest committed head before this slice was committed.
- `bin/verify` passed on 2026-05-13.

## Remaining

- Commit, push, and watch GitHub CI plus a fresh WAMP Profile Benchmarks run
  because this slice changes the benchmark workflow and audit gate.

# Deployment Audit Runtime Sensitivity

Status: implemented locally with clean local verification. The previous worker
scale-down reassignment plan is implementation-complete and remains blocked
only by PR review/merge and operator RC-tag controls. Hosted evidence for this
deployment-chain tooling/workflow change is pending push and workflow runs.

## Goal

Make the deployment-chain audit distinguish runtime/build-input changes from
test-only package changes so Router Image and WAMP Profile Benchmark evidence
is required only when those artifacts could change.

## Plan

- Narrow Router Image stale-evidence detection to Docker metadata, native
  transport code, package pubspecs, runtime `lib`/hook inputs, router binary
  entrypoints, native install helpers, and image metadata rendering.
- Narrow WAMP Profile Benchmark stale-evidence detection to benchmark workflow,
  benchmark orchestration scripts, native benchmark/transport inputs, package
  pubspecs, and runtime libraries used by the benchmark harness.
- Align the WAMP Profile Benchmarks workflow path filters with those runtime
  inputs so test-only package changes do not start benchmark runs on release
  branches.
- Add a local diagnostic mode to the audit script that prints path sensitivity
  groups for a ref-to-HEAD comparison without requiring GitHub API access.

## Verification

- `bin/test-fast`: passed before edits on 2026-05-17.
- `bash -n bin/audit-github-deployment-chain`: passed.
- `bin/audit-github-deployment-chain --show-sensitive-changes-since f2aeb6d`:
  passed; the prior router test-only change is no longer Router Image or WAMP
  Profile Benchmark sensitive.
- Isolated temp-repo sensitivity diagnostic: passed; router test-only changes
  are ignored by Router Image/WAMP sensitivity and router runtime `lib` changes
  are still marked sensitive.
- `git diff --check`: passed.
- Private-name/local-path scan on touched docs/tooling/workflow paths: passed.
- `bin/test-fast`: passed after edits on 2026-05-17.
- `bin/verify`: passed on 2026-05-17.

## Remaining

- Commit and push the implementation.
- Collect required hosted evidence for the pushed tooling/workflow change.

# Deployment Audit Runtime Sensitivity

Status: implemented with clean local and hosted verification for the
tooling/workflow slice. The previous worker scale-down reassignment plan is
implementation-complete and remains blocked only by PR review/merge and
operator RC-tag controls. A follow-up regression test now covers the local
sensitivity diagnostic and is pending commit/push and hosted evidence.

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
- Add checked regression coverage for that local diagnostic so future audit
  path-filter changes cannot silently reclassify router runtime tests as Router
  Image or WAMP Profile Benchmark inputs.

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
- Commit `02d58c7`: pushed to GitHub on
  `codex/post-rc-production-readiness`.
- Hosted push CI #25987809282: passed.
- Hosted PR CI #25987810049: passed.
- Hosted Dart Package Publish Dry Run #25987810042: passed.
- Hosted WAMP Profile Benchmarks #25987816460: passed.
- Strict deployment-chain audit with latest CI/logs, package dry-run, WAMP
  benchmark, workflow visibility, GHCR visibility, and RC-readiness reporting:
  passed for the enforced gates. Native Artifacts #25983559481 and Router Image
  #25986708938 remain relevant because no native-release-sensitive or
  router-image-sensitive paths changed after those runs.
- `python3 tool/test_audit_github_deployment_chain.py`: passed after adding the
  checked diagnostic regression.
- `bin/test-fast`: passed after wiring the checked diagnostic regression into
  the fast gate on 2026-05-17.
- `bin/verify`: passed after wiring the checked diagnostic regression into the
  full gate on 2026-05-17.

## Remaining

- Commit and push the regression coverage with this state update.
- Collect required hosted evidence for the pushed regression coverage.

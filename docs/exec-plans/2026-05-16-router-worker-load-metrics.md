# Router Worker Load Metrics

Status: complete with hosted evidence
Owner: Codex
Created: 2026-05-16
Last updated: 2026-05-16

## Goal

Expose low-cost per-worker load metrics through the existing router metrics
snapshot and OpenMetrics payload so operators can see whether worker isolates
are unevenly loaded before any autoscaling or load-aware assignment policy is
introduced.

## Scope

- Add per-worker connection, busy, in-flight dispatch, dispatch total,
  completion/error, and observed busy-duration counters to
  `RouterMetricsSnapshot`.
- Render those counters in OpenMetrics with stable worker/isolate labels.
- Keep this slice read-only/observability-only; do not change worker assignment
  or autoscaling behavior.
- Preserve the existing aggregate `worker_count` and `active_connections`
  fields for compatibility.

## Validation

- 2026-05-16: Pre-edit `bin/test-fast` passed.
- 2026-05-16: `dart test packages/connectanum_router/test/router_metrics_service_test.dart -r expanded --chain-stack-traces`
  passed.
- 2026-05-16: `dart analyze packages/connectanum_router` passed.
- 2026-05-16: Full local `bin/verify` passed.
- 2026-05-16: Implementation committed as `1c57ced` and pushed to GitHub
  PR #79.
- 2026-05-16: Hosted push GitHub CI #25969485228 passed with `Fast Checks`
  job #76338815539 and `Full Verify` job #76339069330 green.
- 2026-05-16: Hosted push Dart Package Publish Dry Run #25969485233 passed.
- 2026-05-16: Hosted PR GitHub CI #25969486329 passed with `Fast Checks` and
  `Full Verify` green.
- 2026-05-16: Hosted PR Dart Package Publish Dry Run #25969486325 passed.
- 2026-05-16: `bin/audit-github-deployment-chain --branch codex/post-rc-production-readiness --run-limit 1 --require-clean-latest-ci --require-clean-latest-ci-logs --require-clean-dart-package-publish-dry-run`
  passed with clean latest CI, hosted CI logs/annotations, and relevant hosted
  package dry-run evidence. The audit still reports PR #79 as review-required
  before release-branch promotion.

## Handoff

Complete with local and hosted verification. No worker assignment or autoscaling
behavior changed in this observability-only slice.

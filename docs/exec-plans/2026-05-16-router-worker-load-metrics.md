# Router Worker Load Metrics

Status: complete locally; hosted evidence pending
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

## Handoff

Complete locally. Hosted CI/package/audit evidence is pending until this bundle
is committed and pushed.

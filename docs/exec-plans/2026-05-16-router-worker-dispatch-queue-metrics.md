# Router Worker Dispatch Queue Metrics

Status: complete locally
Owner: Codex
Created: 2026-05-16
Last updated: 2026-05-16

## Goal

Extend the post-RC router worker observability baseline with pending native
handle depth and queue latency metrics, using a bounded boss-owned dispatch
prefetch queue per worker. This gives operators enough signal to identify
workers that are accumulating native handles before any autoscaling or
load-aware assignment policy is introduced.

## Scope

- Add a bounded per-worker pending dispatch queue in the router boss.
- Release prefetched native handles when a worker shuts down or a connection is
  detached before dispatch.
- Expose pending dispatch count, queued dispatch total, total queue latency,
  oldest pending age, most recent queue latency, and peak pending depth in the
  router metrics snapshot.
- Render the new queue metrics through the OpenMetrics exporter with the same
  worker/isolate label shape as the existing worker load metrics.
- Keep autoscaling and load-aware assignment policy out of this slice.

## Validation

- 2026-05-16: Pre-edit `bin/test-fast` passed.
- 2026-05-16: `dart test packages/connectanum_router/test/router_runtime_test.dart -n "prefetches worker dispatches and reports queue metrics" -r expanded --chain-stack-traces`
  passed.
- 2026-05-16: `dart test packages/connectanum_router/test/router_runtime_test.dart -r expanded --chain-stack-traces`
  passed.
- 2026-05-16: `dart test packages/connectanum_router/test/router_metrics_service_test.dart -r expanded --chain-stack-traces`
  passed.
- 2026-05-16: `dart analyze packages/connectanum_router` passed.
- 2026-05-16: `git diff --check` passed.
- 2026-05-16: Full local `bin/verify` passed.

## Handoff

Complete locally. The code path is covered by focused and package-level router
runtime tests, metrics exporter tests, package analysis, diff hygiene, and full
workspace verification. Hosted evidence is still pending until the
implementation is pushed.

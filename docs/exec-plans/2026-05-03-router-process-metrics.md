# Router Process Metrics

Status: active
Owner: Codex
Created: 2026-05-03
Last updated: 2026-05-03

## Goal

Make the router metrics exporter more production-ready by exposing low-cost
process health gauges alongside existing router, realm, and native transport
counters.

## Scope

- Add process-level metrics that are cheap to collect on every scrape.
- Include the new data in both JSON snapshot payloads and OpenMetrics text.
- Keep the exporter scrape-driven; do not add background polling.
- Document the metric names and keep tests pinned to the public payloads.

## Non-Goals

- High-cost heap histograms, allocation sampling, or VM-service dependencies.
- CPU delta sampling that requires periodic background collection.
- Changing the metrics auth model, listener configuration, or route shape.

## Verification Plan

- Pre-change `bin/test-fast`.
- Focused router metrics tests and analyzer.
- `git diff --check`.
- Full `bin/verify` before handoff.
- Push and watch GitHub CI if the implementation is committed.

## Progress

- 2026-05-03: Started after the GitHub deployment-chain audit passed at
  branch head `847f0e4`. Deployment-chain RC blockers remain operator-owned, so
  autonomous code work moved to the next production-readiness area.
- 2026-05-03: Pre-change `bin/test-fast` passed before process metrics edits.
- 2026-05-03: Added router process PID/current RSS/max RSS to
  `RouterMetricsSnapshot`, JSON snapshot payloads, and OpenMetrics output.
  Focused checks passed:
  `dart analyze packages/connectanum_router`,
  `dart test packages/connectanum_router/test/router_metrics_service_test.dart packages/connectanum_router/test/open_metrics_http_server_test.dart -r expanded`,
  `dart test packages/connectanum_router/test/router_metrics_test.dart packages/connectanum_router/test/router_runtime_test.dart --name metrics -r expanded`,
  and `git diff --check`.
- 2026-05-03: Full local `bin/verify` passed after the process metrics slice.
- 2026-05-03: Committed the process metrics implementation as `02748b2`
  (`router: expose process metrics`).

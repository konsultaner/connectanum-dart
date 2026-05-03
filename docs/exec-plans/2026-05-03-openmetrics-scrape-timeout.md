# OpenMetrics Scrape Timeout

Status: completed
Owner: Codex
Created: 2026-05-03
Last updated: 2026-05-03

## Goal

Harden the router OpenMetrics exporter so a stalled metrics collection path does
not hold Prometheus scrape connections indefinitely.

## Scope

- Add a configurable OpenMetrics collection timeout with a safe default.
- Parse and serialize the timeout through router settings/config codecs.
- Apply the timeout to HTTP `/metrics` scrapes and the internal
  `connectanum.metrics.openmetrics` RPC path.
- Return an explicit unavailable/error result when collection times out.
- Document the config knob and keep tests pinned to the public behavior.

## Non-Goals

- Moving the exporter into a dedicated isolate.
- Adding high-cost heap/CPU sampling.
- Changing metrics names, auth semantics, listener configuration, or the
  existing scrape path.

## Verification Plan

- Pre-change `bin/test-fast`.
- Focused config, OpenMetrics HTTP, and metrics service tests.
- `dart analyze packages/connectanum_router`.
- `git diff --check`.
- Full `bin/verify` before handoff.
- Push and watch GitHub CI if committed.

## Progress

- 2026-05-03: Branch-head GitHub deployment audit passed at `4d633d6` before
  starting this slice; only operator-owned deployment findings remain.
- 2026-05-03: Pre-change `bin/test-fast` passed.
- 2026-05-03: Added `open_metrics.collection_timeout_ms` to router config,
  settings codec, metrics exporter metadata, and `/metrics` collection. A
  timed-out scrape now returns HTTP `503`; the internal OpenMetrics RPC maps the
  timeout to the existing WAMP runtime-error path.
- 2026-05-03: Focused checks passed:
  `dart analyze packages/connectanum_router`,
  `dart test packages/connectanum_router/test/open_metrics_http_server_test.dart packages/connectanum_router/test/router_config_loader_test.dart -r expanded`,
  and `git diff --check`.
- 2026-05-03: Full local `bin/verify` passed after the OpenMetrics timeout
  implementation, including Rust native/FFI tests, Dart package suites, bench
  integration coverage, full router tests, MCP router-hosted smoke coverage,
  and Chrome/Dart2Wasm WebSocket transport tests.

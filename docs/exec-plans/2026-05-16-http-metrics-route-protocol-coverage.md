# HTTP Metrics Route Protocol Coverage

Status: complete; hosted CI and deployment-chain evidence clean
Owner: Codex
Created: 2026-05-16
Last updated: 2026-05-16

## Goal

Close the remaining observability confidence gap for configured HTTP bridge
metrics scraping: the `/metrics` route already maps to
`connectanum.metrics.openmetrics`, but native integration coverage only proved
the route over HTTP/1.1. Add HTTP/2 and HTTP/3 scrape evidence so downstream
operators can expose metrics on the same configured listener without requiring
a dedicated sidecar proxy.

## Scope

- Add native integration coverage for a configured HTTP/2 `/metrics` scrape.
- Add native integration coverage for a configured HTTP/3 `/metrics` scrape
  using the existing native test client helper when available.
- Preserve the existing dedicated `metrics.open_metrics.listen` exporter and
  the existing configured HTTP/1.1 bridge route behavior.
- Bundle the pending hosted-evidence bookkeeping from the previous implementation
  commit with this code/test change.

## Verification Plan

- Pre-edit `bin/test-fast`.
- Focused native integration tests for HTTP metrics route protocol coverage.
- `dart analyze packages/connectanum_router`.
- Full `bin/verify` before handoff.
- Push and watch hosted CI/package dry-run if committed.

## Progress

- 2026-05-16: Selected this slice after confirming MCP is RC-ready and the
  current roadmap gap is production-readiness evidence for the HTTP bridge, not
  another MCP helper permutation or a duplicate metrics action type.
- 2026-05-16: Added native HTTP/2 and HTTP/3 `/metrics` route scrape coverage
  alongside the existing HTTP/1.1 route test.
- 2026-05-16: Focused native integration tests passed:
  `dart test packages/connectanum_router/test/router_integration_native_test.dart -n "OpenMetrics payload over HTTP" -r expanded --chain-stack-traces`.
- 2026-05-16: `dart analyze packages/connectanum_router` passed.
- 2026-05-16: Full local `bin/verify` passed.
- 2026-05-16: Committed as `e218a4c`
  (`test: cover metrics route protocols`) and pushed to GitHub PR #79.
- 2026-05-16: Hosted evidence for `e218a4c` is clean: push-triggered GitHub
  CI #25968754290 passed with `Fast Checks` job #76336825294 and
  `Full Verify` job #76337078085 green; push-triggered Dart Package Publish
  Dry Run #25968754293 passed; PR-triggered GitHub CI #25968755601 passed with
  `Fast Checks` and `Full Verify` green; PR-triggered Dart Package Publish Dry
  Run #25968755616 passed; and the strict deployment-chain audit passed with
  clean latest CI, hosted CI logs/annotations, and relevant hosted package
  dry-run evidence.

## Handoff

Complete with clean local and hosted verification. PR #79 remains blocked only
by review/merge requirements before release-branch promotion.

# MCP Router Catalog Refresh Ordering

Status: active; implementation and complete local verification green, hosted
verification pending

## Goal

Keep concurrent router-hosted MCP requests from refreshing and rebinding one
shared route endpoint's WAMP tool and metadata catalog out of order.

## Context

The native boss intentionally dispatches HTTP request handlers without awaiting
earlier requests. Modern stateless requests for the same route and principal
reuse one `_RouterMcpEndpoint`, while `_refreshTools()` awaits realm snapshots
and per-procedure/topic authorization before replacing the endpoint's shared
tool registry and catalog signatures. Two requests could therefore overlap,
allow a later refresh to commit first, and then let the older refresh overwrite
the newer catalog and emit stale list-change notifications.

## Plan

1. Add a native-router regression that blocks the first catalog authorization
   pass and proves a second HTTP connection cannot enter the same endpoint's
   refresh concurrently.
2. Queue endpoint catalog refreshes in request arrival order, recover the queue
   after an individual refresh error, and leave downstream WAMP tool execution
   and HTTP response delivery outside the queue.
3. Run catalog-focused native tests, router analysis, `bin/test-fast`, and
   `bin/verify`; publish the implementation and collect exact-head deployment
   evidence.

## Progress

- 2026-08-08: Pre-change `bin/test-fast` passed.
- 2026-08-08: The fail-first regression reproduced two overlapping catalog
  authorization passes on separate HTTP connections sharing one public route
  endpoint (`Expected false`, `Actual true`).
- 2026-08-08: `_RouterMcpEndpoint` now chains catalog refreshes through an
  endpoint-local future tail. A failed refresh remains visible to its caller
  but the next queued refresh can still run.
- 2026-08-08: The focused concurrency regression passes after the change.
- 2026-08-08: All five catalog-focused native-router tests and router analysis
  pass. Post-change `bin/test-fast` also passes the complete fast regression,
  live WAMP benchmark, package-boundary smoke, and Router CLI consumer matrix.
- 2026-08-08: Final exact-code `bin/verify` passed with zero formatting
  changes, 114 Rust core tests plus serializer integrations, 52 Rust FFI tests
  plus the focused metrics check, 360 Dart core tests, all 97 MCP tests, the
  complete 280-case MCP/client suite, all 96 benchmark tests including 36 live
  WAMP workloads, all 399 router tests, the 6-case remote-auth process, the
  13-case native follow-up, every generated and globally activated consumer
  smoke, and Chrome/Dart2Wasm.

## Handoff

- Commit and publish with the accumulated hosted-evidence bookkeeping, then
  watch the exact-head GitHub deployment chain.

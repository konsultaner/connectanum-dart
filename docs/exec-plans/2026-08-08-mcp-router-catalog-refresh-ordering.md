# MCP Router Catalog Refresh Ordering

Status: complete; implementation commit `9841711e` is published on both
maintained `master` branches, and local plus exact-head hosted verification is
green

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
- 2026-08-08: Commit `9841711e` is published on both maintained `master`
  branches. Exact-head GitHub CI `31256464937`, Dart Package Publish Dry Run
  `31256464936`, WAMP Profile Benchmarks `31256464944` attempt 2, and Router
  Image dry run `31256554182` passed. The first WAMP attempt recorded two
  transient 64 KiB Dart AES pub/sub throughput samples below the 1.200 Mbps
  floor; the unchanged exact-head retry passed. Coverage artifact `9021712010`,
  successful WAMP artifact `9021684344`, Router Image preview artifact
  `9021545729`, and Docker build records `9021593115` and `9021592792` were
  uploaded.
- 2026-08-08: The comprehensive strict deployment-chain audit exited zero
  with clean exact-head CI jobs and logs, package and native-release evidence,
  loaded-image MCP runtime smoke, multi-architecture image build, WAMP profile
  gates, branch protection, workflow visibility, and public router-package
  visibility all ready. RC tagging remains a separate release approval
  decision and was not changed.

## Handoff

- Milestone complete. Select the next router-hosted MCP or downstream
  application readiness gap from the roadmaps and current implementation
  evidence.

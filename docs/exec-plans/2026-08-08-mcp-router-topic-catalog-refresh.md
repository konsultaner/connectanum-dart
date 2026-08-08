# MCP Router Topic Catalog Refresh

Status: active; implementation and complete local verification green, hosted
verification pending

## Goal

Keep router-hosted MCP procedure and topic metadata current when a live WAMP
topic appears without changing the serialized MCP tool catalog, so direct JSON
and compatibility-era Streamable HTTP clients observe the same current API.

## Scope

- In scope: router MCP refresh identity, live topic discovery, direct JSON and
  compatibility-era Streamable metadata handlers, focused native-router
  coverage, and normal local plus hosted verification.
- Out of scope: changing WAMP authorization, adding new MCP tools or protocol
  methods, changing pub/sub queue policy, persisting catalog snapshots, or
  changing the application-facing catalog schema.

## Preconditions

- Local head and both maintained `master` branches start at `d1972248`.
- The preceding pub/sub catalog-refresh continuity checkpoint passed local
  verification, all exact-head hosted workflows, and the comprehensive strict
  deployment-chain audit.
- Its final hosted-evidence bookkeeping remains intentionally uncommitted for
  bundling with this implementation commit.
- Complete pre-change `bin/test-fast` passed on 2026-08-08.

## Plan

1. Add a fail-first native-router regression that reads the WAMP API through
   direct JSON and Streamable HTTP, creates a live topic without changing any
   MCP tool definition, and reads both catalogs again.
2. Include the normalized WAMP procedure and topic catalogs in the router MCP
   endpoint refresh signature so retained meta-tool handlers never outlive the
   API snapshot that they describe.
3. Prove both transports expose the new topic while maintaining the existing
   protocol lifecycle and public client boundary.
4. Run focused router tests and analysis, `bin/test-fast`, and `bin/verify`;
   publish the implementation and collect exact-head hosted evidence.

## Verification

- focused `router_integration_native_test.dart` regression
- `dart analyze packages/connectanum_router`
- `bin/test-fast`
- `bin/verify`

## Decision Log

- 2026-08-08: Source audit found that `_RouterMcpEndpoint._refreshTools()`
  serializes only MCP tool definitions when deciding whether to install the
  freshly built handlers. `connectanum.api.list` and
  `connectanum.api.describe` are bound to that fresh WAMP API snapshot, but a
  topic-only catalog change leaves every tool definition unchanged. The
  endpoint therefore retains meta-tool handlers that describe the old topic
  catalog indefinitely.
- 2026-08-08: Complete pre-change `bin/test-fast` passed before adding the
  regression or changing behavior. It covered 360 Dart core tests, all 97 MCP
  tests, the complete 280-case MCP/client suite, all 96 benchmark cases
  including 36 live WAMP workloads, every generated and globally activated
  consumer smoke, the Router CLI lifecycle matrix, and focused native/router
  follow-ups.
- 2026-08-08: The fail-first native-router regression read the public WAMP API
  through direct JSON and Streamable HTTP, added the authorized live topic
  `app.events.catalog_refresh`, and read both catalogs again. The first direct
  JSON assertion failed because it still received the complete pre-change
  catalog without that topic, reproducing the stale bound handler while the
  MCP tool definitions remained unchanged.
- 2026-08-08: Router MCP refresh identity now includes sorted serialized WAMP
  procedures and topics plus API name and metadata alongside the MCP tool
  definitions. A catalog-only change therefore installs the freshly bound
  handlers, while normalization avoids refreshes caused only by discovery
  ordering. The focused direct JSON and Streamable regression passes.
- 2026-08-08: Post-change `bin/test-fast` passes with 360 Dart core tests, all
  97 MCP tests, the complete 280-case MCP/client suite, all 96 benchmark tests
  including 36 live WAMP workloads, every generated and globally activated
  consumer smoke, the Router CLI lifecycle matrix, and focused native/router
  follow-ups.
- 2026-08-08: Final exact-code `bin/verify` passes with zero formatting
  changes, 114 Rust core tests plus serializer integrations, 52 Rust FFI tests
  plus the focused metrics check, 360 Dart core tests, all 97 MCP tests, the
  complete 280-case MCP/client suite, all 96 benchmark tests including 36 live
  WAMP workloads, all 397 router tests, the 6-case remote-auth process, the
  13-case native follow-up, every generated and globally activated consumer
  smoke, and Chrome/Dart2Wasm.

## Handoff

- Publish the implementation and collect exact-head hosted deployment
  evidence.

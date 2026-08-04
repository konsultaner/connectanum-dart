# Exec Plan: MCP Client Session Lifecycle Concurrency

## Status

Completed locally; exact-head hosted verification remains.

## Goal

Prevent delayed compatibility-session HTTP responses from validating against
or clearing a newer MCP lifecycle state established while the request was in
flight.

## Scope

- Pin session-bound request headers and response validation to the session
  generation that started each request.
- Keep successful DELETE cleanup local to the lifecycle generation it
  terminated.
- Keep 401/404 cleanup from stale session-bound requests from clearing a newer
  session and resume cursor.
- Preserve existing synchronous session-failure cleanup, response-header
  validation, modern stateless behavior, and direct JSON isolation.
- Prove same-session-id replacement safety so identifier comparison alone
  cannot hide a stale response.

## Non-Goals

- Serialize all MCP requests or forbid concurrent consumer operations.
- Change router session identifiers or HTTP status semantics.
- Add new MCP protocol versions, capabilities, or OAuth behavior.
- Make direct JSON helpers participate in Streamable HTTP lifecycle state.

## Verification

- Pre-change `bin/test-fast`.
- Fail-first public-client regressions for delayed DELETE success and delayed
  session-failure responses across re-initialization.
- Focused client analysis and Streamable HTTP client tests.
- Generated client-only consumer-package smoke.
- Full `bin/verify` before handoff.
- Exact-head hosted workflows and strict deployment-chain audit after push.

## Progress

- 2026-08-04: Selected after response-header integrity. `deleteSession()`
  snapshots whether a session exists but later sends, validates, and clears
  against mutable current state. The shared 401/404 cleanup path similarly
  clears whichever session is current when a delayed response arrives.
- 2026-08-04: Pre-change `bin/test-fast` passed, including the public
  router-hosted MCP consumer matrix and live WAMP progressive RPC, call
  timeout, statistics Meta API, authentication, and control workloads.
- 2026-08-04: Five fail-first regressions reproduced stale lifecycle mutation
  from delayed DELETE success, explicit same-ID manual reattachment, delayed
  404 failure, delayed compatibility polling, and delayed malformed initialize
  validation. Requests now capture an opaque lifecycle generation plus the
  original session, protocol, and cursor state before their first await. Stale
  responses still validate their own lifecycle headers but cannot clear or
  overwrite replacement state, even when re-initialization or caller-managed
  reattachment uses the same session identifier.
- 2026-08-04: Focused client analysis, all 133 Streamable HTTP client tests,
  the generated client-only consumer-package smoke, and post-change
  `bin/test-fast` passed. Full `bin/verify` passed with no formatting or
  analysis findings, 113 Rust core tests, 52 Rust FFI tests, 360 Dart core
  tests, all 94 MCP tests, the complete 213-case MCP/client authorization
  suite, all 96 benchmark tests including live progressive RPC, timeout,
  statistics Meta API, authentication, control, mixed-serializer, large
  payload, and E2EE workloads, all 384 router tests, native follow-ups,
  Chrome/Dart2Wasm coverage, and every isolated and globally activated
  consumer/CLI smoke.

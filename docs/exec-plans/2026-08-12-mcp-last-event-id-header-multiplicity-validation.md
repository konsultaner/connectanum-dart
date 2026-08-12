# MCP Last-Event-ID Header Multiplicity Validation

Status: complete; implementation and local verification green, hosted evidence
pending

## Goal

Make router-hosted MCP reject repeated case-insensitive `Last-Event-ID`
headers on authenticated compatibility-era GET polling before one scalar
resume cursor can select or consume SSE replay state.

## Context

The native HTTP boundary retains normalized duplicate-header-name evidence,
and router-hosted MCP now rejects repeated Origin, Authorization,
`MCP-Protocol-Version`, and `MCP-Session-Id` names at their corresponding
trust boundaries. Compatibility-era GET polling still selects one
`Last-Event-ID` scalar after principal authentication and endpoint lookup.
A request can therefore carry one valid retained event ID and one conflicting
case-variant value and let native scalar selection decide the replay cursor.
The fix must preserve protected-route authentication precedence, unknown
session handling, stateless 2026 behavior, and the existing rule that
`Last-Event-ID` is meaningful only for compatibility GET polling.

## Plan

1. Preserve the completed protocol-header checkpoint's hosted-evidence notes
   and run the required workflow, Serena, overlap, completed-plan,
   both-roadmap, and green pre-change fast-matrix checks.
2. Add a fail-first protected-session regression that sends a syntactically
   valid SSE cursor before a conflicting case-variant cursor and proves one
   selected scalar can otherwise drive cursor/history validation.
3. Reject repeated normalized `Last-Event-ID` names on authenticated
   compatibility GET requests before cursor syntax/history validation or SSE
   replay mutation, using the canonical session-aware JSON-RPC error.
4. Extend real native HTTP integration and the neutral installed-router
   consumer smoke, including successful continued use of the original session
   after rejection.
5. Run focused and full verification, capture the durable convention, publish
   the implementation checkpoint, and audit the exact-head GitHub deployment
   chain.

## Progress

- 2026-08-12: Repository workflow, Serena, overlap, completed-plan, both
  roadmaps, and exact-head hosted-CI preflights passed. The only startup changes
  are the completed protocol-header checkpoint's expected hosted-evidence
  notes; the scheduled wrapper, child Codex process, and live runlock belong to
  this run, and no unrelated same-repository editor exists.
- 2026-08-12: Required pre-change `bin/test-fast` passed, including 360 core
  tests, 101 MCP tests, the complete 280-case client/MCP matrix, all 97
  benchmark cases and 37 live WAMP workloads, router-hosted and installed
  consumer smokes, and native follow-ups.
- 2026-08-12: The fail-first protected-session regression preserved
  bearer-authentication precedence and reproduced scalar cursor selection:
  authenticated GET with two case-variant `Last-Event-ID` names returned the
  first cursor's `Unknown MCP SSE Last-Event-ID` error instead of rejecting the
  repeated request header.
- 2026-08-12: Authenticated compatibility GET now rejects normalized repeated
  `Last-Event-ID` names after endpoint ownership and Accept validation but
  before scalar cursor parsing, history lookup, or SSE replay. The response is
  canonical session-aware HTTP 400 JSON-RPC; bearer-free requests still return
  401 and unknown sessions retain their established precedence.
- 2026-08-12: Focused runtime and real native HTTP coverage pass. The neutral
  installed-router consumer reports
  `lastEventIdHeaderMultiplicityValidation: true`, retains the original
  Streamable session after rejection, and continues through direct JSON,
  resources/prompts, WAMP metadata, pub/sub, refresh/revoke, and deletion.
- 2026-08-12: Full `bin/verify` passed with zero formatting changes, 114 Rust
  core tests, 52 Rust FFI tests, 360 Dart core tests, 101 MCP tests, the
  complete 280-case client/MCP matrix, all 97 benchmark cases and 37 live WAMP
  workloads, all 436 router tests, six remote-auth integrations, 13 native
  follow-ups, every generated and installed consumer smoke, and
  Chrome/Dart2Wasm. The checkpoint is ready to publish; exact-head hosted
  deployment evidence remains.

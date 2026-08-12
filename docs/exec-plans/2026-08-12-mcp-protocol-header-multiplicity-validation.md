# MCP Protocol Header Multiplicity Validation

Status: complete; implementation and local verification green, hosted evidence
pending

## Goal

Make router-hosted MCP reject repeated case-insensitive
`MCP-Protocol-Version` headers after route-principal authentication but before
protocol-era selection, session lookup, mutation, or deletion.

## Context

The native HTTP boundary retains normalized duplicate-header-name evidence,
but router-hosted MCP still selects one scalar protocol version before it
decides whether a request is modern/stateless or compatibility/session based.
A request can carry a supported compatibility version followed by a conflicting
case-variant stateless version and operate through whichever value survives
scalar selection. Origin, Authorization, and session-header multiplicity are
already fail-closed; protocol negotiation needs the same deterministic boundary
without weakening protected-route authentication precedence, CORS preflight,
or Protected Resource Metadata discovery.

## Plan

1. Preserve the completed session-header checkpoint's hosted-evidence notes and
   run the required workflow, Serena, overlap, completed-plan, both-roadmap, and
   green pre-change fast-matrix checks.
2. Add a fail-first protected-session regression that sends a supported
   compatibility version before a conflicting case-variant stateless version
   and proves the selected scalar can otherwise mutate a live session.
3. Reject repeated normalized `MCP-Protocol-Version` names after authentication
   and before protocol/session validation, endpoint lookup, or session deletion,
   using a sessionless canonical JSON-RPC error.
4. Extend real native HTTP integration and the neutral installed-router
   consumer smoke across POST, GET, and DELETE, including a successful request
   on the original session after rejection.
5. Run focused and full verification, capture the durable convention, publish
   the implementation checkpoint, and audit the exact-head GitHub deployment
   chain.

## Progress

- 2026-08-12: Repository workflow, Serena, overlap, completed-plan, both
  roadmaps, and exact-head hosted-CI preflights passed. The only startup changes
  are the completed session-header checkpoint's expected hosted-evidence notes;
  the scheduled wrapper, child Codex process, and live runlock belong to this
  run, and no unrelated same-repository editor exists.
- 2026-08-12: Required pre-change `bin/test-fast` passed. The fail-first
  protected-session regression then reproduced the bug: authenticated DELETE
  with supported compatibility and conflicting case-variant stateless protocol
  headers returned HTTP 202 instead of 400 and removed the live session.
- 2026-08-12: Router-hosted MCP now rejects normalized protocol-header
  duplicates after successful principal authentication and before protocol or
  session validation, returning sessionless HTTP 400 with canonical JSON-RPC
  text. The focused auth/session regression passes and still uses the original
  session afterward. Router analysis, shell syntax, diff hygiene, the full
  native integration matrix, and the isolated installed/global consumer smoke
  all pass with POST, GET, and DELETE coverage.
- 2026-08-12: Full `bin/verify` passed with zero formatting changes, 114 Rust
  core tests, 52 Rust FFI tests, 360 Dart core tests, 101 MCP tests, the complete
  280-case client/MCP matrix, all 97 benchmark cases and 37 live WAMP workloads,
  all 436 router tests, six remote-auth integrations, 13 native follow-ups,
  every generated and installed consumer smoke, and Chrome/Dart2Wasm. The
  checkpoint is ready to publish; exact-head hosted deployment evidence remains.

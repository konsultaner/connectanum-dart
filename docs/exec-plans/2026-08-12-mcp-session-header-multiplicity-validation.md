# MCP Session Header Multiplicity Validation

Status: active; implementation and local verification green, hosted evidence pending

## Goal

Make router-hosted MCP reject repeated case-insensitive `MCP-Session-Id`
headers after route-principal authentication but before endpoint lookup,
session mutation, or deletion, even when the first collapsed value names a
valid live session.

## Context

The native HTTP boundary retains normalized duplicate-header-name evidence,
but router-hosted MCP still selects one scalar session ID. A request can carry
both a live session ID and a conflicting value, then operate on whichever
field survives scalar selection. Origin and Authorization multiplicity are
already fail-closed; the session header must have the same deterministic
boundary without weakening the established authentication precedence.

## Plan

1. Preserve the completed Origin checkpoint's hosted-evidence notes and run
   the required workflow, Serena, overlap, completed-plan, both-roadmap, and
   green pre-change fast-matrix checks.
2. Add a fail-first regression that sends a live session ID before a
   case-variant conflicting value on a session operation and proves the live
   session would otherwise be selected.
3. Reject repeated normalized `MCP-Session-Id` names after authentication and
   before protocol/session validation, endpoint lookup, or session deletion.
4. Extend real native HTTP integration and the neutral installed-router
   consumer smoke, including a successful request on the original session
   after rejection.
5. Run focused and full verification, capture the durable convention, publish
   the implementation checkpoint, and audit the exact-head GitHub deployment
   chain.

## Progress

- 2026-08-12: Repository workflow, Serena, overlap, completed-plan, both
  roadmaps, and exact-head hosted-CI preflights passed. The only startup
  changes are the completed Origin checkpoint's expected hosted-evidence
  notes; the scheduled wrapper, child Codex process, and live runlock belong
  to this run, and no unrelated same-repository editor exists.
- 2026-08-12: Required pre-change `bin/test-fast` passed, including the native
  router, installed-package, authenticated MCP, JSON-response, pub/sub, and
  neutral consumer smoke matrices.
- 2026-08-12: The fail-first protected-session regression sent the live
  session ID before a conflicting case-variant value. The authenticated
  DELETE returned HTTP 202 and deleted the selected live session instead of
  the required HTTP 400; the bearer-free form still returned HTTP 401,
  confirming the required authentication precedence.
- 2026-08-12: Router-hosted MCP now rejects normalized repeated
  `MCP-Session-Id` names immediately after route-principal authentication and
  before protocol/session validation or endpoint lookup. The canonical HTTP
  400 JSON-RPC response does not reflect a session ID. Synthetic and real
  native HTTP coverage proves POST, GET, and DELETE rejection, and a later
  valid operation proves the original session remains usable.
- 2026-08-12: The isolated installed-router consumer passes and reports
  `sessionHeaderMultiplicityValidation: true` while continuing through direct
  JSON, Streamable HTTP, WAMP metadata, pub/sub, refresh/revoke, and session
  deletion without private project assumptions. Focused router analysis,
  formatting, diff hygiene, runtime/native tests, and shell smoke checks pass.
- 2026-08-12: Post-change `bin/verify` passes with zero formatting changes,
  114 Rust core tests, 52 Rust FFI tests, 360 core tests, 101 MCP tests, the
  complete 280-case client/MCP suite, all 96 benchmark cases and 36 live WAMP
  workloads, all 436 router tests, six remote-auth integrations, 13 native
  follow-ups, every generated and installed consumer smoke, and
  Chrome/Dart2Wasm. The implementation is ready to publish; exact-head hosted
  workflows and the strict deployment-chain audit remain.

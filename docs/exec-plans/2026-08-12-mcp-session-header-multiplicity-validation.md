# MCP Session Header Multiplicity Validation

Status: complete; implementation, local verification, and exact-head hosted
evidence green

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
- 2026-08-12: Initial implementation commit `90c6c26c7fd8` reached both
  maintained `master` branches. Package dry-run workflow `31613021020` and
  WAMP Profile Benchmarks `31613021138` passed, but exact-head CI
  `31613021553` exposed a Linux benchmark-harness race: two sequential
  bind-close ephemeral-port reservations could return the same port for the
  RawSocket and WebSocket listeners, causing native router configuration to
  fail before the WAMP transport suite ran.
- 2026-08-12: The benchmark harness now holds both ephemeral sockets open
  until it has reserved distinct listener ports, and a focused contract test
  prevents regression. The repaired focused benchmark file passes all 27
  cases. Post-repair `bin/verify` passes with zero formatting changes, 114
  Rust core tests, 52 Rust FFI tests, 360 core tests, 101 MCP tests, the
  complete 280-case client/MCP suite, all 97 benchmark cases and 37 live WAMP
  workloads, all 436 router tests, six remote-auth integrations, 13 native
  follow-ups, every generated and installed consumer smoke, and
  Chrome/Dart2Wasm. The repaired checkpoint is ready to publish; a fresh
  exact-head hosted chain and the strict deployment-chain audit remain.
- 2026-08-12: Repair commit `ceacac7c5141` reached both maintained `master`
  branches and the clean-commit strict package gate again passed all seven
  synchronized `3.0.0-beta` archives with zero warnings. Exact-head CI
  `31616008117` passed Fast Checks, Full Verify, Dart VM Coverage, Codecov
  upload, and coverage artifact `9149903984`. Dart Package Publish Dry Run
  `31616008120` and WAMP Profile Benchmarks `31616008129` passed; the WAMP
  run uploaded artifact `9149490364`.
- 2026-08-12: Exact-head Router Image dry run `31617676907` passed loaded-image
  router-hosted MCP smoke and multi-architecture build validation. It uploaded
  preview artifact `9149937044` and Docker build records `9150077924` and
  `9150077263`. The comprehensive strict deployment-chain audit exits zero
  with clean exact-head CI logs and every required branch, workflow, public
  package, unchanged native-release relevance, loaded-image MCP,
  multi-architecture image, package-publish, and benchmark gate clean. Its
  non-gating RC summary remains intentionally not ready because no approved
  current-head RC publication was requested.

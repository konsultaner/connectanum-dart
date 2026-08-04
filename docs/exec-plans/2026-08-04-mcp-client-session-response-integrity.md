# Exec Plan: MCP Client Session Response Integrity

## Status

Completed.

## Goal

Ensure a compatibility-era Streamable HTTP client accepts a newly assigned
`MCP-Session-Id` only from a successful `initialize` response and never lets a
later POST or GET response silently replace its established session.

## Scope

- Validate every captured response session header before changing client
  state.
- Allow successful initialization to establish or replace the local session.
- Require later standard POST and SSE GET responses to omit the session header
  or echo the already-active session ID.
- Preserve the active session ID and resume cursor when a later response
  carries a different valid session ID.
- Keep direct JSON helpers lifecycle-free and preserve existing DELETE,
  rejected-initialize, malformed-header, auth-error, and HTTP 404 cleanup
  semantics.
- Repair the existing proactive router idle-expiry timer when verification
  proves an early wake can silently lose the cleanup callback.

## Non-Goals

- Change router session allocation or the intended idle-expiry semantics.
- Add session rotation as a Connectanum extension.
- Change sessionless MCP 2026 requests or request-scoped subscriptions.
- Change protocol-version negotiation in this milestone.

## Verification

- Pre-change `bin/test-fast`.
- Fail-first public-client regressions for mismatched standard POST and SSE GET
  response session headers.
- Focused client analysis/tests and generated consumer-package smoke.
- Full `bin/verify` before handoff.
- Exact-head hosted workflows and strict deployment-chain audit after push.

## Progress

- 2026-08-04: Selected after the rejected-initialize cleanup. The legacy
  Streamable HTTP contract assigns a session ID only in the response carrying
  a successful `InitializeResult`, and the client already enforces exact
  response-session identity for DELETE. Normal POST and GET response capture,
  however, currently adopts any different valid session ID and clears the
  existing resume cursor.
- 2026-08-04: Pre-change `bin/test-fast` passed analysis, core/MCP/client
  suites, all 96 benchmark tests, and every isolated and globally activated
  consumer/CLI smoke.
- 2026-08-04: Fail-first public-client regressions reproduce both affected
  paths: a normal JSON POST and an SSE GET each accept `session-2` while the
  request belongs to `session-1`, instead of rejecting the response and
  preserving the established session and resume cursor.
- 2026-08-04: The shared response capture path now permits session assignment
  only for initialize and requires later POST/GET response headers to match the
  active session before state mutation. Focused client analysis, all 119
  Streamable client tests, and the isolated/globally activated client-package
  smoke pass. Advisory local review prompted explicit successful
  re-initialization coverage; DELETE and direct JSON use separate existing
  lifecycle paths.
- 2026-08-04: Full `bin/verify` reproduced the pre-existing router idle-expiry
  subscriber-cleanup failure previously seen on hosted CI. Three repeated
  isolated runs passed, but the fourth still retained its subscription after a
  diagnostic five-second observation window. The deadline timer can therefore
  wake just before the endpoint stopwatch reaches the timeout and return
  without scheduling another check. The router now re-arms that same deadline
  for the remaining interval while preserving the original timeout; the
  regression keeps its original one-second cleanup-observation budget.
- 2026-08-04: The exact native idle-expiry regression passed 10 consecutive
  runs after the timer re-arm fix. Final `bin/verify` passes formatting and
  analysis, 113 Rust core and 52 Rust FFI tests, 360 Dart core tests, all 94
  MCP tests, the complete 199-case MCP/client authorization suite, all 96
  benchmark tests with live WAMP workloads, all 384 router tests, native
  follow-ups, Chrome/Dart2Wasm coverage, and every isolated and globally
  activated consumer/CLI smoke. One HTTP/3 FFI handshake timed out on its
  first attempt and passed on the built-in retry. Exact-head hosted workflows
  and the strict deployment-chain audit remain after push.
- 2026-08-04: Implementation commit `57a41f5` is on both maintained `master`
  branches. Exact-head CI `30917453920`, Dart Package Publish Dry Run
  `30917448873`, WAMP Profile Benchmarks `30917453719`, and Router Image dry
  run `30919095170` all passed on their first attempts with zero check
  annotations. Coverage artifact `8896223621`, WAMP artifact `8895894527`,
  Router Image preview artifact `8896308893`, and Docker build records
  `8896474266` and `8896473269` were uploaded. The comprehensive strict
  deployment-chain audit passes with clean exact-head CI logs, loaded-image
  MCP runtime smoke, multi-architecture image build, and all required branch,
  workflow, package, publish-dry-run, and benchmark gates clean.

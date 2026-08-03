# Exec Plan: Router Image Modern Method Live-Session Isolation Smoke

## Status

Active.

## Goal

Prove that router-hosted MCP `2026-07-28` GET and DELETE requests carrying a
live compatibility-era `MCP-Session-Id` are rejected as stateless protocol
traffic without polling, terminating, or otherwise mutating the referenced
`2025-11-25` Streamable HTTP session.

## Scope

- Reuse the real public and bearer-protected compatibility pub/sub sessions in
  the canonical loaded Router Image smoke.
- Send modern GET and DELETE requests carrying each live compatibility session
  ID and the protected route's valid bearer grant when required.
- Require HTTP 405, the modern protocol response header, `Allow: POST,
  OPTIONS`, JSON-RPC `invalidRequest`, and no response `MCP-Session-Id` from
  both methods.
- Continue the compatibility session through publish, poll, unsubscribe, and
  compatibility DELETE so the smoke proves the modern method probes did not
  terminate or mutate it.
- Emit one bounded hosted-log marker covering the modern standard/direct POST
  and GET/DELETE isolation checks for public and protected routes.

## Non-Goals

- Change the already-shipped MCP 2026 stateless method policy.
- Add a modern session lifecycle or permit modern clients to terminate
  compatibility sessions.
- Duplicate the complete native-router or generated-consumer method matrices.

## Verification

- Pre-change `bin/test-fast`.
- A focused failing Router Image method-isolation contract before runner
  implementation.
- The complete Router Image contract suite and canonical runner against a
  freshly built Linux/amd64 image.
- Full `bin/verify` before handoff.
- Exact-head CI and Router Image dry run, relevant package/native/WAMP
  evidence, hosted log inspection, and the comprehensive strict
  deployment-chain audit after the implementation push.

## Progress

- 2026-08-03: Selected after the modern standard/direct POST live-session
  isolation checkpoint completed. The MCP 2026 stateless core already rejects
  GET and DELETE, but canonical loaded-image evidence did not prove that those
  methods cannot poll or terminate a real compatibility session when they
  carry its live identifier.
- 2026-08-03: Pre-change `bin/test-fast` passed, including analysis, all 19
  Router Image contracts, all MCP and client authorization tests, live WAMP
  benchmark workloads, and isolated plus globally activated consumer smokes.
- 2026-08-03: The focused contract failed first because the runner had no
  modern GET/DELETE live-session probe. The new probe requires HTTP 405,
  `Allow: POST, OPTIONS`, the modern protocol header, JSON-RPC `-32600`, and
  no response session ID from both methods before the compatibility lifecycle
  continues. Python compilation, all 20 Router Image contracts, and the
  complete runner against a freshly built Linux/amd64 image pass. The bounded
  raw evidence reports `modern_methods_rejected=true get=true delete=true` for
  public and protected routes, and all four globally activated package-client
  evidence lines remain green. Full `bin/verify` also passed, including
  formatting, 113 Rust core tests, 52 Rust FFI tests plus the focused metrics
  follow-up, the updated 20-test Router Image contract, 360 core tests, all 94
  MCP tests, the complete 193-case MCP/client authorization suite, all 96
  benchmark tests with live WAMP workloads, every isolated and globally
  activated consumer smoke, the complete 380-case router suite, 13 focused
  native-forwarding tests, and Chrome/Dart2Wasm coverage. Hosted exact-head
  evidence remains.

# Exec Plan: Router Image Compatibility Principal Isolation Smoke

## Status

Implementation complete; hosted evidence pending.

## Goal

Prove that a second valid bearer principal cannot POST to, poll, or terminate
another principal's live protected MCP `2025-11-25` Streamable HTTP session in
the packaged Router Image, while the authenticated owner retains the complete
pub/sub and session lifecycle.

## Scope

- Add a second neutral ticket identity to the canonical Router Image smoke
  configuration and issue a real router bearer grant for it.
- Reuse the primary principal's live protected compatibility pub/sub session
  ID in POST, GET, and DELETE requests authenticated as the second principal.
- Require HTTP 404, the `Unknown MCP HTTP session` JSON-RPC error, the
  compatibility protocol response header, and the request session ID response
  header from every rejected method, without a Bearer challenge.
- Continue the primary owner through publish, poll, unsubscribe, and DELETE so
  rejected cross-principal requests demonstrably neither consume events nor
  terminate the session.
- Revoke both issued access tokens and emit one bounded hosted-log marker for
  valid-principal POST/GET/DELETE isolation.

## Non-Goals

- Change router authentication policy or Streamable session ownership.
- Duplicate the generated consumer's complete direct JSON, WAMP Meta API, and
  compatibility lifecycle matrix for its second principal.
- Add authorization checks to the anonymous public MCP route.
- Change token refresh, expiry, or insufficient-scope behavior.

## Verification

- Pre-change `bin/test-fast`.
- A focused failing Router Image principal-isolation contract before runner
  implementation.
- Python compilation and the complete Router Image contract suite.
- The canonical runner against a freshly built current-source local image,
  followed by the canonical Linux/amd64 image in the hosted Router Image dry
  run.
- Full `bin/verify` before handoff.
- Exact-head CI and Router Image dry run, relevant package/native/WAMP
  evidence, hosted log inspection, and the comprehensive strict deployment
  chain audit after the implementation push.

## Progress

- 2026-08-04: Selected after the packaged image proved missing and unknown
  bearers cannot GET or DELETE a protected live compatibility session. Native
  router and neutral generated-consumer coverage already prove that a second
  valid principal receives `404 Unknown MCP HTTP session`; the canonical
  loaded-image evidence did not exercise that principal-keyed boundary.
- 2026-08-04: Pre-change `bin/test-fast` passed. The focused Router Image
  contract then failed first because the runner had no valid-other-principal
  compatibility-session isolation helper.
- 2026-08-04: The loaded-image configuration now exposes a second neutral
  ticket identity, and the runner issues and later revokes both principals'
  router grants. The new probe requires authenticated 404 responses with the
  compatibility protocol and requested session headers, no Bearer challenge,
  and `Unknown MCP HTTP session` for POST, GET, and DELETE before the owner
  completes its pub/sub and DELETE lifecycle.
- 2026-08-04: Python compilation, all 23 Router Image contracts, and the
  complete runner against a freshly rebuilt current-source Linux/arm64 image
  passed. The raw marker records valid-other-principal POST/GET/DELETE
  isolation, and all four globally activated package-client evidence lines
  remain green. Docker Desktop's credential helper blocked the canonical
  tagged-base refresh, so the local image used the transparent cached-base
  path; the canonical Linux/amd64 Dockerfile build remains part of exact-head
  hosted evidence.
- 2026-08-04: Full `bin/verify` passed formatting, all Rust and FFI suites,
  360 core tests, all 94 MCP tests, the complete 193-case MCP/client
  authorization suite, all 96 benchmark tests with live WAMP workloads, every
  isolated and globally activated consumer smoke, the complete 380-case router
  suite, 13 native-forwarding follow-ups, and Chrome/Dart2Wasm coverage.

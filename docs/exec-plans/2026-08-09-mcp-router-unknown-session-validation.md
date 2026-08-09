# MCP Router Unknown Session Validation

Status: active

## Goal

Make terminated, expired, cross-route, and cross-principal compatibility-era
Streamable HTTP sessions authoritative before request-body validation, and
ensure no unknown-session response advertises the rejected session ID.

## Context

The maintained MCP `2025-11-25` Streamable HTTP contract requires a server to
return HTTP 404 after terminating a session. Router-hosted GET already resolves
the session before replay validation, but POST currently checks request size,
decodes JSON, and validates standard request headers before looking up the
session. A request carrying a deleted or otherwise inaccessible session can
therefore receive a body/header error instead of the required 404. Ordinary
unknown-session GET, POST, and DELETE responses also echo the caller-supplied
`MCP-Session-Id`, unlike the fail-closed concurrent-deletion paths.

The governing transport requirement is the maintained MCP specification:
<https://modelcontextprotocol.io/specification/2025-11-25/basic/transports>.

## Plan

1. Run the pre-change fast regression matrix and add deterministic
   native-router coverage for a deleted session whose subsequent POST has an
   invalid body, plus unknown-session GET/POST/DELETE header isolation.
2. Reproduce the validation-before-session and stale response-header behavior,
   then resolve authenticated Streamable POST sessions before inspecting their
   body and omit session headers from every unknown-session response.
3. Prove live sessions retain normal validation behavior, direct JSON remains
   sessionless even when a stale compatibility header is present, and a fresh
   compatibility session remains usable.
4. Run focused tests, post-change `bin/test-fast`, and full `bin/verify`; bundle
   prior hosted-evidence bookkeeping with the implementation, push both
   maintained remotes, and audit exact-head hosted evidence.

## Progress

- 2026-08-09: Repository-workflow and Serena preflight completed. The prior
  implementation and hosted verification are green, only its expected
  evidence notes were dirty at startup, and no unrelated same-repository Codex
  process or stale lock exists.
- 2026-08-09: Pre-change `bin/test-fast` passed end to end. A focused
  native-router assertion then reproduced the defect: an unknown compatibility
  session received a 404 that echoed its caller-supplied session ID.
- 2026-08-09: Authenticated Streamable POST now resolves its route/principal
  session before request-size, JSON, and MCP method-header validation. Missing,
  terminated, cross-route, and cross-principal sessions return a shared
  sessionless 404; readable request IDs are preserved. A valid `initialize`
  carrying a caller-supplied session ID retains its existing 400 validation,
  and direct JSON continues to ignore compatibility session state.
- 2026-08-09: Focused native-router coverage passes for malformed and
  oversized requests after DELETE, live-session parse errors, route/principal
  isolation, direct JSON isolation, HTTP/3 setup when its local helper is
  available, and the broad MCP pub/sub smoke.
- 2026-08-09: The first post-change fast run exposed one stale generated
  consumer assertion that still expected unknown GET/DELETE responses to echo
  the rejected session. The smoke now requires sessionless 404 responses; its
  isolated rerun and the restarted full `bin/test-fast` both pass, including
  all package, consumer, router CLI, native, and benchmark coverage.
- 2026-08-09: Full `bin/verify` passed with zero formatting changes, 114 Rust
  core tests plus serializer integrations, 52 Rust FFI tests, 360 Dart core
  tests, 101 MCP tests, the complete 280-case client MCP matrix, all 96
  benchmark tests and 36 live WAMP workloads, all 415 router tests, isolated
  consumer/CLI and remote-auth checks, 13 native follow-ups, and
  Chrome/Dart2Wasm coverage.
- 2026-08-09: Implementation commit `dd02be9` was pushed to both maintained
  remotes. Exact-head Router Image dry run `31329571529` then reproduced a
  second stale smoke contract: the loaded-image cross-principal 404 check still
  required the rejected session ID to be echoed. A focused Python fixture
  reproduced the mismatch before the image smoke was corrected to require a
  sessionless response and publish `requested_session_omitted=true` evidence.
  All 27 image-smoke contracts and the restarted complete `bin/test-fast` pass.
  The repeated full `bin/verify` also passes the complete Rust, Dart, native,
  consumer, router, benchmark, remote-auth, and Chrome/Dart2Wasm matrix.
  Replacement exact-head hosted evidence remains.

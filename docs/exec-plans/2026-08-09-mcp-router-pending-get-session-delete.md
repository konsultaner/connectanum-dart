# MCP Router Pending GET Session Delete

Status: active

## Goal

Ensure deleting a compatibility-era Streamable HTTP session irrevocably stops
an in-flight GET/SSE poll that is awaiting router-hosted catalog refresh, so the
removed endpoint cannot later acknowledge the stale session or replay queued
notifications.

## Context

Streamable POST re-checks endpoint disposal after asynchronous catalog refresh
and message handling. GET acquires the same endpoint and awaits the same refresh
without an equivalent lifecycle guard before selecting and sending SSE events.
A concurrent DELETE can therefore remove and dispose the endpoint while a stale
GET still holds its object reference and pending replay state.

## Plan

1. Run the pre-change fast regression matrix and add a deterministic native
   router regression that blocks GET catalog authorization, deletes the MCP
   session, and releases the stale poll with a queued resource notification.
2. Reproduce stale GET acknowledgment or replay after DELETE, then make the GET
   lifecycle fail closed before SSE event selection.
3. Prove the stale response is sessionless 404 with no queued notification,
   the deleted session stays gone, and a replacement session can poll normally.
4. Run focused tests, post-change `bin/test-fast`, and full `bin/verify`; bundle
   prior hosted-evidence bookkeeping with the implementation, push both
   maintained remotes, and audit exact-head hosted evidence.

## Progress

- 2026-08-09: Repository-workflow and Serena preflight completed. Exact-head
  local and hosted verification is green, no unrelated same-repository Codex
  process or stale lock exists, and only the expected prior hosted-evidence
  notes were dirty at startup.
- 2026-08-09: Pre-change `bin/test-fast` passed the complete core, MCP,
  client/auth, benchmark and 36-case live-WAMP, generated consumer, globally
  activated, Router CLI, native runtime, and router-worker follow-up matrix.
- 2026-08-09: A deterministic native-router regression reproduced the defect:
  a compatibility GET blocked in catalog authorization returned HTTP 200 and
  replayed a queued `notifications/resources/updated` event after DELETE had
  removed its Streamable session.
- 2026-08-09: GET now re-checks endpoint disposal after catalog refresh and
  before selecting replay events. Focused coverage proves a sessionless 404,
  no stale notification, and normal replacement-session polling; the adjacent
  pending-delete action matrix and router analysis also pass.
- 2026-08-09: Post-change `bin/test-fast` passed the complete core, MCP,
  client/auth, benchmark and 36-case live-WAMP, generated consumer, globally
  activated, Router CLI, native runtime, and router-worker follow-up matrix.
- 2026-08-09: `bin/verify` passed formatting, Rust core/FFI tests, both
  native-integration groups, Dart package suites, all 36 live-WAMP profiles,
  generated and globally activated consumer smokes, the 414-test router suite,
  isolated remote-auth/native-forwarding follow-ups, and Chrome/Dart2Wasm.

# MCP Router Deleted-Session Action Side Effects

Status: complete

## Goal

Ensure deleting a compatibility-era Streamable HTTP session irrevocably stops
an in-flight router-hosted MCP action after authorization, before it can publish
an event or invoke another WAMP side effect for an endpoint that no longer
exists.

## Context

The router rejects a stale Streamable request before dispatch and before its
HTTP response, but individual WAMP actions await asynchronous authorization
inside that interval. If DELETE disposes the endpoint while that decision is
blocked, an allowed decision can currently resume into the physical publish or
call before the outer lifecycle guard converts the eventual response to a
sessionless 404. Endpoint teardown must prevent both stale acknowledgment and
the irreversible downstream action.

## Plan

1. Run the pre-change fast regression matrix and add a deterministic native
   router regression that blocks a compatibility publish's action
   authorization, deletes the MCP session, and observes the independent direct
   JSON subscriber.
2. Reproduce that stale completion can publish despite the deleted request
   returning 404, then make authorization completion lifecycle-aware before any
   WAMP action proceeds.
3. Prove the deleted session remains gone, the independent subscription sees no
   stale event, and a replacement session can publish normally.
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
- 2026-08-09: The fail-first native-router regression deleted a Streamable
  session while its publish action authorization was blocked. The stale caller
  received HTTP 404 after release, but an independent sessionless direct JSON
  subscriber still received the publication, proving the irreversible side
  effect escaped endpoint teardown.
- 2026-08-09: Authorization now fails closed when its endpoint is disposed
  before provider lookup, while a provider or policy decision is pending, or
  before physical WAMP call, publish, subscribe, resource-read, or unsubscribe
  work begins. Independent regressions prove a stale publish reaches no direct
  JSON subscriber and a stale tool call invokes no registered procedure; the
  adjacent pending-subscribe and cross-era deletion-coexistence regressions
  also pass, and router analysis is clean.
- 2026-08-09: Post-change `bin/test-fast` passes the complete core, MCP,
  client/auth, benchmark and 36-case live-WAMP, generated consumer, globally
  activated, Router CLI, native runtime, and router-worker follow-up matrix.
  A local-model advisory review prompted the explicit stale-call regression;
  its other concurrency observations are covered by same-isolate endpoint
  ownership and the final checks immediately before physical WAMP helpers.
- 2026-08-09: Full `bin/verify` passes formatting, 114 Rust core tests, 52
  Rust FFI tests, 360 Dart core tests, 101 MCP tests, the complete 280-case
  MCP/client suite, 96 benchmark tests with all 36 live WAMP workloads, 413
  router tests, isolated consumer and globally activated CLI smokes,
  remote-auth isolation, native follow-ups, and Chrome/Dart2Wasm.

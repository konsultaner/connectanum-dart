# MCP Router Unknown-Session Resume-Cursor Evidence

Status: completed

## Goal

Prove that a compatibility-era Streamable HTTP GET carrying an unknown or
terminated session identifier receives the required sessionless HTTP 404 even
when it also carries a stale `Last-Event-ID` resume cursor.

## Context

The maintained MCP `2025-11-25` Streamable HTTP contract requires a server to
return HTTP 404 for requests carrying a terminated session identifier. Router
code already resolves the authenticated endpoint before validating the resume
cursor, but existing native-router coverage separately proves unknown-session
handling and live-session cursor rejection. It does not pin their interaction.

The governing transport requirement is:
<https://modelcontextprotocol.io/specification/2025-11-25/basic/transports>.

Route-level rate limiting remains an intentionally pre-dispatch operational
guard and is outside this focused compatibility contract.

## Plan

1. Run the pre-change fast regression matrix and inspect session/cursor ordering
   with Serena.
2. Add a native-router regression for an unknown compatibility session carrying
   a syntactically valid but stale resume cursor.
3. Prove the response is HTTP 404 without `MCP-Session-Id`, while the equivalent
   active-session stale cursor remains HTTP 400.
4. Run focused checks, post-change `bin/test-fast`, and full `bin/verify`;
   bundle the preceding hosted-evidence notes with this implementation before
   publication.

## Progress

- 2026-08-10: Repository workflow, Serena, overlap, roadmap, and active-state
  preflight completed. The preceding POST-negotiation implementation is
  published and hosted-green; only its expected evidence notes were dirty at
  startup.
- 2026-08-10: Symbol inspection confirms endpoint/session lookup precedes both
  `Last-Event-ID` header validation and cursor-history validation. Existing
  coverage proves live-session stale cursors return HTTP 400, but does not
  combine a stale cursor with an unknown session.
- 2026-08-10: Pre-change `bin/test-fast` passes the complete fast regression
  flow, including core, MCP, client, real-router WAMP benchmark workloads,
  generated and globally activated package clients, router CLI consumer smoke,
  and native router follow-ups.
- 2026-08-10: Native-router coverage now reuses an event ID emitted by a live
  compatibility session as a realistic stale resume cursor, sends it with an
  unknown session identifier, and proves the response is HTTP 404 without an
  `MCP-Session-Id` response header. The same ingress test continues to prove an
  active session carrying an unknown cursor receives HTTP 400.
- 2026-08-10: The focused native-router ingress/session test, post-change
  `bin/test-fast`, formatting, `git diff --check`, and full `bin/verify` pass.
  Full verification covered the complete Rust and Dart workspace, 360 core
  tests, 101 MCP tests, the 280-case client MCP matrix, all 96 benchmark tests
  including 36 live WAMP workloads, all 416 router tests, remote-auth
  isolation, native follow-ups, every generated and globally activated
  consumer/CLI smoke, and Chrome/Dart2Wasm.

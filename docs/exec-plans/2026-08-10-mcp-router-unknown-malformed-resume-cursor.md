# MCP Router Unknown-Session Malformed Resume-Cursor Evidence

Status: completed

## Goal

Prove that a compatibility-era Streamable HTTP GET carrying an unknown or
terminated session identifier receives the required sessionless HTTP 404 even
when it also carries a syntactically malformed `Last-Event-ID` header.

## Context

The maintained MCP `2025-11-25` Streamable HTTP contract requires a server to
return HTTP 404 for requests carrying a terminated session identifier. Router
code already resolves the authenticated endpoint before validating the resume
cursor, and the preceding checkpoint pins the same precedence for a
syntactically valid but stale cursor. It does not yet cover malformed control
bytes, which ordinary Dart HTTP clients reject before transmission and must
therefore be exercised through the router's synthetic native handshake.

The governing transport requirement is:
<https://modelcontextprotocol.io/specification/2025-11-25/basic/transports>.

An invalid or unsupported `MCP-Protocol-Version` intentionally remains HTTP 400
because that same specification explicitly mandates the response; protocol
version precedence is outside this focused session/cursor regression.

## Plan

1. Run the pre-change fast regression matrix and inspect session/cursor ordering
   with Serena.
2. Add synthetic-router coverage for an unknown compatibility session carrying
   a malformed resume cursor that contains a control character.
3. Prove the response is HTTP 404 without `MCP-Session-Id`, while the equivalent
   active-session malformed cursor remains HTTP 400.
4. Run the focused test, post-change `bin/test-fast`, and full `bin/verify`;
   bundle the preceding hosted-evidence notes with this implementation before
   publication.

## Progress

- 2026-08-10: Repository workflow, Serena, overlap, roadmap, and active-state
  preflight completed. The preceding resume-cursor evidence is published and
  hosted-green; only its expected evidence notes were dirty at startup.
- 2026-08-10: Pre-change `bin/test-fast` passes the complete fast regression
  flow, including core, MCP, client, real-router WAMP benchmark workloads,
  generated and globally activated package clients, router CLI consumer smoke,
  and native router follow-ups.
- 2026-08-10: Synthetic-router coverage now sends an unknown claimed session
  with `Last-Event-ID: cursor\nnext` and proves HTTP 404 without an
  `MCP-Session-Id` response header. The existing live-session request carrying
  the same malformed cursor continues to prove HTTP 400.
- 2026-08-10: The focused router runtime test, formatting,
  `git diff --check`, post-change `bin/test-fast`, and full `bin/verify` pass.
  Full verification covered 114 Rust core tests plus serializer integrations,
  52 Rust FFI tests plus the metrics follow-up, 360 Dart core tests, 101 MCP
  tests, the 280-case client MCP matrix, all 96 benchmark tests including 36
  live WAMP workloads, all 416 router tests, isolated remote authentication,
  native follow-ups, every generated and globally activated consumer/CLI
  smoke, and Chrome/Dart2Wasm.
- 2026-08-10: Implementation commit `5da8fd76` is published to both maintained
  `master` branches. Exact-head CI `31357410453`, Dart Package Publish Dry Run
  `31357410459`, WAMP Profile Benchmarks `31357410431`, and Router Image dry
  run `31358396109` all pass. Retained artifacts are Dart VM coverage
  `9051430005`, WAMP profile evidence `9051243524`, Router Image preview
  `9051442946`, and Docker build records `9051512167` and `9051511659`. The
  comprehensive strict deployment-chain audit exits zero with clean exact-head
  CI jobs and logs plus every required package, still-relevant native release,
  fresh-image MCP smoke, multi-architecture image build, WAMP,
  workflow-visibility, branch-protection, and public GHCR gate ready. Only the
  deliberately unapproved next RC tag remains outside this milestone.

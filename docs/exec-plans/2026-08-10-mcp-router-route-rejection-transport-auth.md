# MCP Router Route-Rejection Transport Auth

Status: complete; implementation and local verification green

## Goal

Make configured router-hosted MCP method and protocol rejections honor the
route's TLS and mutual-TLS requirements before returning MCP 405/426 responses,
without moving bearer, Origin, or session validation out of the full MCP
handler.

## Context

Configured MCP `HttpRouteMatch.methods` and `HttpRouteMatch.protocols`
mismatches now enter the MCP handler so protected routes authenticate and
responses remain sessionless. Those mismatch branches still return before the
generic HTTP transport-auth gate runs. An insecure request can therefore
observe an MCP route rejection from a route that requires TLS or mTLS, while a
fully matched request is rejected at the transport boundary.

Public and protected MCP behavior inside the handler, including Origin
precedence, Protected Resource Metadata discovery, bearer challenges, and
session isolation, must remain unchanged. Non-MCP route rejection behavior and
rate-limit placement must also remain unchanged.

## Plan

1. Preserve the preceding hosted-evidence notes, run the pre-change fast gate,
   and add fail-first native coverage for TLS-gated method rejection and
   mTLS-gated protocol rejection.
2. Defer configured MCP method/protocol responses until route transport auth
   has evaluated the response route, while continuing to defer bearer
   authentication to the MCP handler for those mismatches.
3. Run focused formatting, analysis, and native route regression checks, then
   post-change `bin/test-fast` and full `bin/verify`.
4. Update durable project state, bundle implementation and verification notes
   with the code checkpoint, publish both maintained branches, and audit the
   exact-head GitHub deployment chain when hosted evidence is required.

## Progress

- 2026-08-10: Repository workflow, Serena, overlap, active-state, and both
  roadmap preflights completed. Both maintained `master` heads equal
  `9743126d`; only the preceding checkpoint's expected hosted-evidence notes
  were dirty at startup.
- 2026-08-10: The first pre-change `bin/test-fast` attempt passed all local
  repository and benchmark tests before a temporary consumer package failed to
  fetch `crypto` from pub.dev. A full retry again passed the repository suites
  but was interrupted after the temporary dependency fetch stopped making
  progress. No code changes were present during either run.
- 2026-08-10: The fail-first native regression reproduced the TLS-gated MCP
  method mismatch returning HTTP 405 instead of the transport boundary's HTTP
  403. Its paired mTLS protocol case pins the same precedence requirement for
  HTTP 426.
- 2026-08-10: Configured MCP method/protocol mismatches now defer their MCP
  response until transport auth evaluates the resolved response route. TLS and
  mTLS are enforced there, while bearer authentication remains in the full MCP
  handler so invalid Origin, public metadata, bearer challenges, and session
  isolation retain their established precedence.
- 2026-08-10: Focused router formatting, analysis, diff hygiene, the public and
  protected MCP rejection matrix, the new TLS/mTLS regression, and the ordinary
  HTTP transport-auth/method/protocol tests pass.
- 2026-08-10: Post-change `bin/test-fast` passes analysis, 360 core tests, 101
  MCP tests, the 280-case client MCP matrix, all 96 benchmark tests including
  36 live WAMP workloads, every isolated and globally activated consumer and
  CLI smoke, maintained router-hosted MCP live variants, and native router
  follow-ups.
- 2026-08-10: Full `bin/verify` passes with zero formatting changes, 114 Rust
  core tests, 52 Rust FFI tests, 360 Dart core tests, 101 MCP tests, the
  complete 280-case client MCP matrix, all 96 benchmark tests including 36
  live WAMP workloads, all 418 router tests, six remote-auth integrations, 13
  native follow-ups, every isolated/global consumer and CLI smoke, and
  Chrome/Dart2Wasm. The implementation checkpoint is ready to publish and
  audit.

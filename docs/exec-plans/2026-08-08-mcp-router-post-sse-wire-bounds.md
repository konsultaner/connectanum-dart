# MCP Router POST/SSE Wire Bounds

Status: active; implementation and full local verification green, publication
and hosted evidence pending

## Goal

Make the router-hosted MCP `max_response_bytes` policy bound the complete
encoded compatibility POST/SSE response body, not only its JSON-RPC data
payload, while preserving the active session and keeping replay state
transactional on rejection.

## Scope

- In scope: exact SSE wire-byte accounting for compatibility POST responses,
  pre-stream rejection, sequence-reservation rollback, active-session and
  direct-JSON recovery, focused native coverage, public configuration wording,
  and normal local plus hosted verification.
- Out of scope: changing the route option or default, truncating successful
  responses, changing GET/SSE polling semantics, changing modern request-
  scoped listener limits, or adding speculative MCP protocol features.

## Preconditions

- Both maintained `master` branches and the local feature branch start at
  `db50a3f7`.
- The preceding SSE replay-history byte-bound checkpoint passed complete local
  verification, exact-head hosted workflows, and the comprehensive strict
  deployment-chain audit.
- Its final hosted-evidence bookkeeping remains intentionally uncommitted for
  bundling with this implementation commit.
- Pre-change `bin/test-fast` passed on 2026-08-08.

## Plan

1. Add a fail-first native-router regression whose raw JSON-RPC result fits
   `max_response_bytes` but whose primer plus response SSE framing exceeds it.
2. Serialize the POST/SSE batch once before opening the native response stream,
   reject an oversized encoded body with the bounded JSON-RPC HTTP error, and
   roll back the tentative SSE sequence reservation.
3. Prove the compatibility session remains reusable, no resume cursor or
   response session header is captured from the rejection, a smaller
   compatibility request succeeds and replays, direct JSON remains usable, and
   DELETE still cleans up.
4. Run focused checks, `bin/test-fast`, and `bin/verify`; update durable state,
   publish to both maintained branches, then collect exact-head workflow and
   strict deployment-chain evidence.

## Verification

- focused `router_integration_native_test.dart` regression
- `dart analyze packages/connectanum_router`
- `bin/test-fast`
- `bin/verify`

## Decision Log

- 2026-08-08: Source audit found that operation responses compare only raw
  UTF-8 JSON bytes with `max_response_bytes`. Compatibility POST/SSE then adds
  a primer event, event IDs, retry and data prefixes, and delimiters without
  rechecking the actual HTTP body. A near-limit JSON result can therefore
  exceed the advertised response ceiling and immediately consume more replay
  history than the response policy allows.
- 2026-08-08: Complete pre-change `bin/test-fast` passed before adding the
  regression or changing implementation.
- 2026-08-08: The fail-first native regression built a JSON-RPC tool result
  whose raw UTF-8 encoding is exactly the configured 4096-byte response limit.
  The router returned it successfully as a larger POST/SSE body instead of
  rejecting the encoded wire response.
- 2026-08-08: Compatibility POST/SSE batches are now encoded once before the
  native response stream opens. The router compares that complete body with
  the route ceiling, restores the tentative batch when it is oversized, and
  returns the existing bounded HTTP 500 JSON-RPC error without a response
  session header.
- 2026-08-08: The focused native regression and
  `dart analyze packages/connectanum_router` pass. Coverage proves the rejected
  boundary response leaves the active compatibility session and client cursor
  unchanged, then proves a smaller POST/SSE response and primer-cursor replay,
  sessionless direct JSON reuse, and DELETE cleanup.
- 2026-08-08: Post-change `bin/test-fast` and full `bin/verify` pass. Full
  verification covers formatting and analysis, 114 Rust core tests, 52 Rust
  FFI tests plus the focused metrics check, 360 Dart core tests, all 96 MCP
  tests, the complete 280-case MCP/client suite, all 96 benchmark tests
  including 36 live WAMP workloads, every generated and globally activated
  consumer smoke, all 393 router tests, the 6-case remote-auth process, the
  13-case native follow-up, and Chrome/Dart2Wasm.

## Handoff

- Implementation and full local verification are green. Review, commit, and
  publish the code plus durable state to both maintained branches, then collect
  exact-head workflow and strict deployment-chain evidence.

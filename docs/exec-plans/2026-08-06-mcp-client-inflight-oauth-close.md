# MCP Client In-Flight OAuth Close

Status: complete

## Goal

Make `McpStreamableHttpClient.close()` terminate OAuth discovery,
registration, token-exchange, refresh, and revocation requests that are
already in flight, including when the client uses a caller-owned shared
`HttpClient`.

## Context

The completed terminal-close milestone prevents new OAuth network helpers from
starting after close and already cancels in-flight ordinary MCP requests and
response-body readers. OAuth helpers still send through the same HTTP transport
without registering their active requests with the client lifecycle, so an
authorization request waiting on headers or a response body can survive client
shutdown. Closing the entire caller-owned transport is not acceptable because
a replacement MCP client must remain able to reuse it.

## Plan

1. Preserve the green pre-change fast-suite baseline and add fail-first
   regressions for OAuth work waiting on response headers and response-body
   completion through a caller-owned transport.
2. Add a shared, bounded request-lifecycle hook to the standalone OAuth HTTP
   helpers and connect client-owned wrapper calls to the existing request
   cancellation machinery plus deterministic operation completion.
3. Cover discovery, registration, code exchange, refresh, and revocation while
   preserving standalone helper behavior and shared-transport reuse.
4. Run focused analysis/tests, the neutral public consumer smoke, and
   `bin/verify`.
5. Update project state, commit and push the implementation with its evidence,
   then audit the exact-head GitHub deployment chain.

## Verification

- The pre-change `bin/test-fast` started on 2026-08-06. The new fail-first
  regressions were added before the long command completed, so that run failed
  only on the two intentional one-second timeout reproductions. The exact
  starting head retained the prior checkpoint's green local and hosted
  verification evidence.
- The fail-first lifecycle regression reproduced both missing boundaries:
  close left an OAuth request waiting for response headers pending, and also
  left protected-resource discovery pending while reading a response body.
- `dart analyze packages/connectanum_client` passed with no issues.
- The focused OAuth suites passed all 38 cases, including protected-resource
  and authorization-server discovery, dynamic registration, authorization-code
  exchange, refresh, revocation, and the new lifecycle regressions.
- The Streamable HTTP client plus lifecycle suites passed all 163 cases, and
  the complete MCP/client authorization suite passed all 243 cases.
- `python3 tool/test_mcp_consumer_package_boundary.py` passed all 19 source
  contracts. The source and globally activated neutral client-only package
  smoke both passed the blocked-discovery close and shared-transport reuse
  lifecycle.
- Post-change `bin/test-fast` passed on 2026-08-06.
- `bin/verify` passed on 2026-08-06 with no formatting changes: 113 Rust core
  tests plus the serializer integration cases, 52 Rust FFI tests, 360 Dart
  core tests, all 94 MCP tests, the complete 243-case MCP/client suite, all 96
  benchmark tests including live router workloads, all 384 router tests, the
  13-case native-forwarding follow-up, every isolated and globally activated
  package smoke, and Chrome/Dart2Wasm WebSocket coverage.

## Outcome

All six `McpStreamableHttpClient` OAuth network wrappers now register their
opened requests with the client lifecycle and race the operation against a
redacted terminal-close signal. Closing the MCP client aborts work blocked on
response headers or response-body completion with the deterministic OAuth
`StateError`, while a caller-owned shared `HttpClient` remains open and usable
by a replacement client. The standalone OAuth helpers preserve their existing
behavior and expose only an optional request-open lifecycle callback.

# MCP OAuth Introspection Response Bounds

Status: active

## Goal

Make router OAuth bearer introspection fail closed under a stalled or oversized
upstream response so protected router-hosted MCP requests cannot remain pending
indefinitely or consume unbounded response memory.

## Context

The shipped OAuth HTTP auth provider currently applies `timeout_ms` while
opening the request and waiting for response headers, but reads the response
body without a deadline or size limit. An introspection endpoint can therefore
send headers and then stall forever, or return an arbitrarily large body,
holding a protected MCP request and its router resources open.

The provider should use one total deadline for connection, headers, and body
consumption, enforce a configurable bounded response size, and return redacted
fail-closed auth results for timeout, oversize, malformed JSON, or truncated
transport responses.

## Plan

1. Preserve the green fast-suite baseline and add fail-first provider
   regressions for a body stalled after response headers and an oversized
   introspection response.
2. Apply one total introspection deadline and a bounded body reader with a
   conservative default plus explicit configuration override.
3. Keep invalid, malformed, and interrupted responses fail-closed without
   including token or response contents in surfaced errors.
4. Run focused provider analysis/tests, `bin/test-fast`, and `bin/verify`.
5. Update the public configuration contract and project state, bundle the
   carried hosted-evidence bookkeeping with the implementation commit, push
   both maintained branches, and audit the exact-head deployment chain.

## Verification

- The initial `bin/test-fast` started from implementation head `8c1318d0` on
  2026-08-06. The fail-first tests and implementation landed while its long
  generated-smoke tail was still running; the command completed successfully,
  so a separate post-change run was used as the authoritative fast gate.
- The three fail-first provider regressions reproduced the missing boundaries:
  a response body stalled after headers exceeded the one-second test guard, an
  oversized valid response authenticated successfully, and malformed JSON
  escaped as a `FormatException`.
- Focused router/bench analysis passed with no issues. The provider, bench
  introspection harness, and shipped bench-router config suites passed all 15
  cases, including the three new redacted fail-closed regressions.
- The release-built `http_bearer_provider_smoke.toml` scenario passed all six
  JWT/OAuth protected-route workloads across HTTP/1.1, HTTP/2, and HTTP/3 using
  the real router and the explicitly bounded shipped OAuth provider config.
- Post-change `bin/test-fast` passed on 2026-08-06, including every neutral
  source/global package smoke and the router CLI MCP lifecycle matrix.
- Full `bin/verify` passed on 2026-08-06 with no formatting changes, 113 Rust
  core tests plus serializer integrations, 52 Rust FFI tests, 360 Dart core
  tests, all 94 MCP tests, the complete 247-case MCP/client suite, all 96
  benchmark tests with live-router workloads, all 387 router tests, the
  13-case native-forwarding follow-up, every isolated and globally activated
  package smoke, and Chrome/Dart2Wasm coverage.

## Outcome

The router OAuth introspection provider now applies one monotonic deadline to
connection, response headers, and complete response-body consumption. It caps
the body at 64 KiB by default with `max_response_bytes` / `maxResponseBytes`
overrides and returns redacted fail-closed results for timeout, oversize,
malformed JSON, and interrupted IO. The shipped provider benchmark config
declares both limits explicitly. Local verification is complete; exact-head
hosted evidence remains.

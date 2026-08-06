# MCP HTTP Auth Operation Bounds

Status: implementation complete; hosted evidence pending

## Goal

Bound router HTTP-auth issue, challenge, refresh, and revoke operations across
request opening, response headers, response bodies, and local challenge work,
while preserving caller-owned HTTP transport reuse and redacting oversized
server responses.

## Context

OAuth discovery, registration, token, and revocation helpers already apply
explicit deadlines and response byte limits. `ConnectanumHttpAuthClient`,
which downstream applications use to obtain router-issued grants before
constructing an MCP client, still waits indefinitely and decodes each complete
response with `utf8.decodeStream`. A stalled auth bridge can therefore retain
an operation forever, and a successful or rejected bridge response can buffer
an arbitrary body before validation.

The deadline must cover a multi-round challenge as one operation, including a
caller authentication callback. Timeout or overflow must abort only the
operation's requests, prevent a late callback from opening another request,
leave a shared `HttpClient` reusable, and avoid surfacing the oversized body in
the typed error.

## Plan

1. Preserve the green fast-suite baseline and add fail-first local-server
   regressions for oversized auth responses.
2. Add validated public deadline and response-byte settings with conservative
   defaults shared by issue, challenge, refresh, and revoke operations.
3. Race every complete auth operation against one timer, abort its active or
   late-opened requests on timeout, and bound response bytes before UTF-8/JSON
   decoding.
4. Prove stalled headers, stalled bodies, paused challenge callbacks,
   successful/error overflow, typed redaction, late-request suppression, and
   same-client shared-transport recovery.
5. Run focused analysis/tests, `bin/test-fast`, and `bin/verify`; then bundle
   the implementation with milestone records and audit exact-head hosted
   evidence after pushing both maintained branches.

## Verification

- Pre-change `bin/test-fast` passed on 2026-08-06 with 360 core tests, all 94
  MCP tests, the complete 264-case MCP/client suite, all 96 benchmark/live-
  router tests, every neutral generated and globally activated consumer/CLI
  smoke, and the focused native/router follow-ups.
- The oversized-success fail-first regression emitted a valid grant before
  the response cap was implemented.
- Focused analysis passed for `connectanum_client` and `connectanum_mcp`.
- The combined HTTP-auth and public IO-boundary regression set passed all 37
  cases, including delayed request opening, stalled headers and bodies, a
  paused challenge callback, multibyte success/error overflow, typed error
  redaction, and same-client transport recovery.
- The complete MCP/client regression set passed all 271 cases.
- Post-change `bin/test-fast` passed on 2026-08-06 with 360 core tests, all 95
  MCP tests, the complete 271-case MCP/client suite, all 96 benchmark/live-
  router tests, every neutral generated and globally activated consumer/CLI
  smoke, and the focused native/router follow-ups.
- Final exact-code `bin/verify` passed with zero formatting changes; 113 Rust
  core tests plus serializer integrations; 52 Rust FFI tests; 360 Dart core,
  95 MCP, 271 MCP/client, 96 benchmark/live-router, and 387 router tests; all
  13 focused native-forwarding regressions; every neutral consumer package and
  CLI smoke; and Chrome Dart2Wasm WebSocket coverage.

## Outcome

Router HTTP-auth issue, challenge, refresh, and revoke operations now share a
validated 30-second total operation deadline that covers request opening,
headers, bodies, and caller challenge callbacks. Timeout aborts active or
late-opened requests without closing a caller-owned `HttpClient`, and a late
callback cannot begin another auth round. Every response is limited to 64 KiB
of raw bytes before UTF-8 or JSON decoding; overflow uses a public typed error
that never embeds the response body. The settings and error type are available
through the public MCP IO entrypoint. Exact-head hosted workflow and deployment
audit evidence remains pending after the implementation is pushed to both
maintained branches.

# Exec Plan: MCP Client Protocol Negotiation Integrity

## Status

Completed.

## Goal

Make the successful `initialize` result authoritative for Streamable HTTP
protocol negotiation and prevent response headers on later requests from
silently changing the version used by an established client session.

## Scope

- Require every successful standard typed or generic `initialize` response to
  contain a supported, non-empty `result.protocolVersion` before capturing
  session state.
- Require an `MCP-Protocol-Version` response header on successful initialize,
  when present, to match that authoritative result value.
- Require later standard POST and compatibility GET/SSE response version
  headers, when present, to match the already-negotiated version.
- Validate all version and session invariants before mutating client session,
  resume-cursor, or protocol-version state.
- Preserve explicit per-call protocol overrides without treating them as a new
  negotiation, and keep direct JSON helpers lifecycle-free.
- Cover the public typed and generic request paths plus recovery after a
  rejected response.

## Non-Goals

- Add support for protocol versions that the package does not implement.
- Make response version headers mandatory when a server omits them.
- Change modern stateless requests, request-scoped listeners, or direct JSON
  lifecycle behavior.
- Change router protocol selection or introduce in-session renegotiation.

## Verification

- Pre-change `bin/test-fast`.
- Fail-first public-client regressions for malformed or unsupported generic
  initialize results, initialize header/result disagreement, and later POST
  and GET/SSE response-version drift.
- Focused client analysis/tests and generated consumer-package smoke.
- Full `bin/verify` before handoff.
- Exact-head hosted workflows and strict deployment-chain audit after push.

## Progress

- 2026-08-04: Selected after the session-response integrity checkpoint. The
  official lifecycle contract makes `InitializeResult.protocolVersion` the
  negotiated version for the session and requires subsequent HTTP requests to
  use it. The public generic POST path currently accepts a successful
  initialize result without that required field, while shared response-header
  capture can independently assign or later replace the client version.
- 2026-08-04: Pre-change `bin/test-fast` passed analysis, core/MCP/client
  suites, all 96 benchmark tests, live WAMP workloads, and every isolated and
  globally activated consumer/CLI smoke.
- 2026-08-04: Four fail-first public-client regressions reproduce the affected
  paths: generic initialize accepts a result without `protocolVersion`, typed
  initialize accepts a supported response-header/result disagreement, and
  later normal POST and compatibility GET/SSE responses accept a supported
  version that differs from the established version.
- 2026-08-04: Initialize result validation now runs in the shared typed/generic
  response-capture path before session state changes. The result version is
  required and supported, an optional response echo must agree, and normal
  POST/batch plus GET/SSE response echoes must match active state. Caller-
  supplied one-request overrides remain non-negotiating. Focused analysis and
  all 124 Streamable client tests pass.
- 2026-08-04: Advisory local review prompted a direct-path audit and clearer
  mismatch diagnostics. Standard generic initialize continues to negotiate,
  while an explicit `postDirect` initialize-shaped payload remains fully
  lifecycle-free; a dedicated regression proves it cannot replace the active
  session, cursor, or negotiated version. Mismatch errors now include expected
  and received values. The client-only generated package smoke passes.
- 2026-08-04: Final `bin/verify` passes formatting and analysis, 113 Rust core
  and 52 Rust FFI tests, 360 Dart core tests, all 94 MCP tests, the complete
  204-case MCP/client authorization suite, all 96 benchmark tests with live
  WAMP workloads, all 384 router tests, native follow-ups, Chrome/Dart2Wasm,
  and every isolated and globally activated consumer/CLI smoke. Exact-head
  hosted workflows and the strict deployment-chain audit remain after push.

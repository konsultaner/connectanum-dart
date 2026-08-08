# MCP Router Catalog Refresh Failure Recovery

Status: active; implementation and complete local verification green, hosted
deployment evidence pending

## Goal

Return bounded, generic MCP HTTP errors when router-hosted catalog authorization
fails unexpectedly, while preserving compatibility-session state and allowing
the shared endpoint's next catalog refresh to recover.

## Context

Every router-hosted MCP GET or POST refreshes the route-visible WAMP catalog
before dispatch. Dynamic authorization-provider exceptions currently escape the
MCP handler into the boss's unawaited HTTP callback. The boss records the
exception but cannot construct a protocol response, so a downstream application
can be left waiting instead of receiving a fail-closed MCP error. The endpoint's
new refresh queue is designed to recover after an individual failure, but that
behavior is not yet proven through either direct JSON or compatibility-era
Streamable HTTP.

## Plan

1. Add a native-router regression that injects one catalog authorization
   failure and proves direct JSON plus compatibility-era Streamable HTTP receive
   generic bounded errors without leaking provider details or mutating session
   state.
2. Convert catalog-refresh exceptions into HTTP 500 MCP JSON-RPC errors at both
   GET and POST request boundaries, preserving existing session headers only
   for established compatibility sessions.
3. Prove the next request on the same shared endpoint succeeds, then run focused
   native-router tests, router analysis, `bin/test-fast`, and `bin/verify`.

## Progress

- 2026-08-08: Pre-change `bin/test-fast` passed the complete fast regression,
  live WAMP benchmark, package-boundary smoke, and Router CLI consumer matrix.
- 2026-08-08: The fail-first native-router regression reproduced an escaped
  authorization-provider exception as the native fallback body
  `http request cancelled`, without the JSON-RPC request id or MCP error.
- 2026-08-08: Router-hosted catalog refresh failures now return a generic MCP
  internal-error response for GET and POST. Stateless and rejected-initialize
  responses omit session state, while established Streamable failures preserve
  the session header and client resume cursor. Operational events retain only
  the exception type, not provider text or a stack trace.
- 2026-08-08: The regression proves direct JSON recovery, tentative initialize
  cleanup and recovery, established Streamable POST recovery, and Streamable
  GET recovery on the next queued refresh. All six catalog-focused native tests
  pass and router analysis is clean.
- 2026-08-08: Post-change `bin/test-fast` passes the complete fast regression,
  all 97 MCP and 280 MCP/client tests, all 96 benchmark tests including 36 live
  WAMP workloads, and the package-boundary plus Router CLI consumer smokes.
- 2026-08-08: Final exact-tree `bin/verify` passes with zero formatting changes;
  114 Rust core tests plus serializer integrations; 52 Rust FFI tests plus the
  focused metrics check; 360 Dart core, 97 MCP, 280 MCP/client, 96 benchmark,
  and 400 Router tests; the 6-case remote-auth and 13-case native follow-ups;
  every generated and globally activated consumer smoke; and Chrome/Dart2Wasm.

## Handoff

- Publish with the accumulated hosted-evidence bookkeeping, watch the exact-head
  deployment chain, and run the strict GitHub deployment audit.

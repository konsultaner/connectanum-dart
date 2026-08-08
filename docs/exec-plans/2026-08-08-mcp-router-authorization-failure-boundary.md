# MCP Router Authorization Failure Boundary

Status: complete; implementation and complete local verification are green,
hosted deployment evidence pending

## Goal

Return bounded, generic MCP tool errors when a router authorization provider
fails during an action check, while keeping direct JSON stateless and preserving
an established Streamable HTTP session for recovery.

## Context

Router-hosted MCP refreshes and authorizes the visible WAMP catalog before each
request. A later authorization check still guards the actual call, publish, or
subscription action. If the provider throws during that second check, the MCP
tool adapters currently serialize `error.toString()` into the consumer-visible
tool result. This can expose authorization-backend detail even though catalog
refresh failures are already bounded and redacted at the HTTP boundary.

## Plan

1. Add a native-router regression that lets catalog authorization succeed and
   injects a provider failure during the actual WAMP tool action through direct
   JSON and compatibility-era Streamable HTTP.
2. Redact provider detail at the shared router authorization boundary, emit
   bounded operational evidence, and retain ordinary authorization denials.
3. Prove the next tool call recovers without direct JSON session state or loss
   of the established Streamable session, then run focused tests, router
   analysis, `bin/test-fast`, and `bin/verify`.

## Progress

- 2026-08-08: Pre-change `bin/test-fast` started from the clean implementation
  baseline. Code inspection identified that action-phase provider exceptions
  reach both standard and direct JSON tool-result serialization with their
  original text.
- 2026-08-08: The fail-first native-router regression reproduced the disclosure
  as `Bad state: action authorization backend detail` in a direct JSON tool
  result after the request's catalog check had succeeded.
- 2026-08-08: The shared router authorization boundary now converts provider,
  provider-cache, and authorizer exceptions into the generic consumer-visible
  message `MCP authorization check failed`. It emits a bounded
  `mcp_authorization_error` event containing only realm, action, and original
  exception type, while preserving that original type in the existing catalog
  refresh event and leaving ordinary deny decisions unchanged.
- 2026-08-08: The regression proves the failed check never invokes the WAMP
  callee, direct JSON stays sessionless, an established Streamable session and
  replay cursor remain usable, both next calls recover, and neither tool results
  nor operational events disclose provider text or a stack trace. Both focused
  authorization-failure tests pass and router analysis is clean.
- 2026-08-08: Exact-tree post-change `bin/test-fast` passes all 97 MCP and 280
  MCP/client cases, all 96 benchmark tests including 36 live WAMP workloads,
  every neutral package/consumer smoke, and the Router CLI lifecycle matrix.
- 2026-08-08: Final exact-code `bin/verify` passes with 397 Dart files already
  formatted; 114 Rust core tests plus serializer integrations; 52 Rust FFI
  tests plus the focused metrics check; 360 Dart core, 97 MCP, 280 MCP/client,
  96 benchmark, and 401 Router tests; the 6-case remote-auth and 13-case native
  follow-ups; every generated and globally activated consumer smoke; and
  Chrome/Dart2Wasm.

## Handoff

- Publish with the accumulated hosted-evidence bookkeeping, watch the exact-head
  GitHub deployment chain, and run the strict deployment audit if that evidence
  is needed for handoff.

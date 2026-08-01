# Exec Plan: MCP Protected Listener and Tool Coexistence

## Status

Completed.

## Goal

Prove that a consumer application can keep a bearer-protected MCP `2026-07-28`
request-scoped listener open while the same stateless client continues to use
ordinary Streamable HTTP and direct JSON tool calls without credential or
session interference.

## Scope

- Add a focused public-client regression showing that a protected
  `subscriptions/listen` request uses its current bearer grant, remains usable
  after caller-managed grant replacement, and does not block a direct JSON
  request that uses the replacement grant.
- Keep the listener open through the request and deliver a notification after
  the direct JSON response, proving that the listener owns independent HTTP
  resources and remains sessionless.
- Extend the isolated generated consumer package so public and protected
  listeners remain active throughout missing-capability checks plus successful
  standard and direct JSON form-MRTR rounds against the native router.
- Add boundary coverage that preserves this neutral downstream-consumer smoke.

## Non-Goals

- Add another MCP protocol extension or change wire behavior.
- Automatically refresh credentials or reconnect established listener streams.
- Add URL-mode elicitation, Roots, Sampling, Tasks, or Apps.
- Prescribe application UI, storage, or authorization policy.

## Verification

- Focused `McpStreamableHttpClient` regression.
- Consumer-package boundary tests.
- Real isolated generated consumer package against the native router.
- `bin/test-fast` before and after the change.
- `bin/verify` before handoff.
- Exact-head GitHub CI, Dart package publish dry run, WAMP benchmark workflow,
  and strict deployment-chain audit after the implementation push.

## Progress

- 2026-08-01: Selected after both roadmaps confirmed that MCP 2026 discovery,
  request-scoped listeners, pub/sub, and form MRTR are individually complete
  while further protocol extensions remain demand-driven. Existing smokes
  closed listeners before exercising other tool paths, leaving their protected
  same-client coexistence unproved.
- 2026-08-01: Pre-change `bin/test-fast` passed.
- 2026-08-01: Added a focused bearer-client regression that opens a modern
  listener with one grant, replaces the grant for a direct JSON tools request,
  then receives a listener notification and closes locally. Both requests
  remain sessionless and use their expected credentials.
- 2026-08-01: Extended the isolated generated consumer package so public and
  protected listeners remain open throughout missing-capability checks plus
  successful standard and direct JSON form-MRTR rounds. The boundary suite now
  preserves this coexistence contract.
- 2026-08-01: The complete client file passed all 111 VM tests, the consumer
  boundary suite passed all 19 tests, the isolated generated consumer completed
  against the native router, and post-change `bin/test-fast` passed with 191
  combined client/MCP authorization tests.
- 2026-08-01: Complete `bin/verify` passed, including formatting, Rust core and
  FFI, Dart VM, live WAMP, generated package, native router, Chrome, and
  Dart2Wasm coverage.

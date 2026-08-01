# Exec Plan: MCP Protected Listener and Pub/Sub Coexistence

## Status

Completed.

## Goal

Prove that a consumer application can keep a bearer-protected MCP `2026-07-28`
request-scoped listener open while the same stateless client completes a direct
JSON WAMP pub/sub lifecycle without credential, connection, or protocol-session
interference.

## Scope

- Add a focused public-client regression covering an authenticated listener
  alongside direct JSON subscribe, publish, poll, and unsubscribe helpers.
- Prove caller-managed grant replacement applies to every subsequent pub/sub
  request while the already-open listener retains its establishment grant.
- Keep the listener usable after the pub/sub lifecycle and preserve explicit
  absence of MCP session and resume state.
- Extend the isolated generated consumer package through the same real
  public/protected router-hosted lifecycle.
- Preserve the neutral consumer-package smoke through boundary assertions.

## Non-Goals

- Add another MCP protocol extension or change listener wire behavior.
- Turn arbitrary WAMP events into MCP protocol notifications.
- Add automatic credential refresh or reconnect established listeners.
- Change consumer application authorization, storage, or UI policy.

## Verification

- Focused `McpStreamableHttpClient` VM regression.
- Consumer-package boundary tests.
- Isolated generated consumer package against the native router.
- `bin/test-fast` before and after the change.
- `bin/verify` before handoff.
- Exact-head GitHub CI, Dart package publish dry run, WAMP benchmark workflow,
  and strict deployment-chain audit after the implementation push.

## Progress

- 2026-08-01: Selected after both roadmaps confirmed that further MCP protocol
  extensions are demand-driven. Protected listeners and direct JSON pub/sub
  were individually complete, but their same-client coexistence was not yet
  preserved by a focused regression or neutral consumer smoke.
- 2026-08-01: Pre-change `bin/test-fast` passed.
- 2026-08-01: Added a focused authenticated-client regression proving an
  already-open request-scoped listener retains its establishment grant while
  direct JSON subscribe, publish, poll, and unsubscribe requests use the
  caller's replacement grant. The listener remains usable and the client
  remains sessionless after the pub/sub lifecycle.
- 2026-08-01: Extended the isolated generated consumer package with the same
  direct pub/sub lifecycle while its public and protected listeners remain
  open against the native router. Boundary assertions preserve the neutral,
  public-package-only smoke contract.
- 2026-08-01: Focused client tests passed with 112 cases, consumer-package
  boundary tests passed with 19 cases, and the isolated consumer smoke passed
  against the public and protected native-router endpoints.
- 2026-08-01: Post-change `bin/test-fast` passed, including 360 core tests, 192
  combined client/MCP authorization tests, 94 MCP tests, 96 benchmark tests,
  the complete router fast suite, and consumer-package smokes.
- 2026-08-01: Complete `bin/verify` passed, including formatting, Rust core and
  FFI, Dart VM, live WAMP, generated package, 380 router, native zero-copy,
  Chrome, and Dart2Wasm coverage.

# Exec Plan: MCP Listener and Streamable Session Coexistence

## Status

Completed.

## Goal

Prove that a consumer application can keep an MCP `2026-07-28`
request-scoped listener open while the same public client switches to the
maintained session protocol, completes an authenticated Streamable HTTP WAMP
pub/sub lifecycle, deletes that session, and continues to own the listener
independently.

## Scope

- Add a focused public-client regression covering listener establishment,
  protocol-era switching, Streamable initialize and initialized notification,
  subscribe, acknowledged publish, event poll, unsubscribe, and session delete.
- Prove the listener keeps its establishment credential while caller-managed
  grant replacement applies to the later Streamable session requests.
- Prove session deletion clears only Streamable session and resume state and
  leaves the request-scoped listener usable and locally cancellable.
- Extend the isolated generated consumer package through the same public and
  protected native-router lifecycle without private project assumptions.
- Preserve the neutral generated-package boundary contract.

## Non-Goals

- Add a new MCP protocol extension or change listener wire behavior.
- Merge the modern request-scoped listener with compatibility-era GET/SSE
  polling or resource replay.
- Reconnect established listeners after credential replacement.
- Change consumer authorization, token refresh, storage, or UI policy.

## Verification

- Focused `McpStreamableHttpClient` VM regression.
- Consumer-package boundary tests.
- Isolated generated consumer package against the native router.
- `bin/test-fast` before and after the change.
- `bin/verify` before handoff.
- Exact-head GitHub CI, Dart package publish dry run, WAMP benchmark workflow,
  and strict deployment-chain audit after the implementation push.

## Progress

- 2026-08-02: Selected after both roadmaps confirmed further MCP extensions are
  demand-driven. Modern listeners already coexist with direct tool and pub/sub
  requests, but their isolation from a complete compatibility-era Streamable
  session lifecycle was not covered by a focused regression or neutral
  consumer smoke.
- 2026-08-02: Pre-change `bin/test-fast` passed.
- 2026-08-02: Added a focused authenticated-client regression proving a
  request-scoped listener retains its establishment grant while the same
  client switches to the session protocol and caller-replaced credentials
  initialize, use, and delete a Streamable HTTP session. Streamable pub/sub
  does not disturb the listener, and session deletion leaves it usable and
  locally cancellable.
- 2026-08-02: Extended the isolated generated consumer package through the
  same public and protected listener plus Streamable pub/sub/session-delete
  lifecycle against the native router. Boundary assertions preserve the
  neutral public-package smoke contract.
- 2026-08-02: The complete client regression file passed with 113 cases,
  consumer-package boundary tests passed with 19 cases, the isolated consumer
  smoke passed, and post-change `bin/test-fast` passed with 360 core tests, 193
  combined client/MCP authorization tests, 94 MCP tests, 96 benchmark tests,
  the complete router fast suite, and generated consumer smokes.
- 2026-08-02: Full `bin/verify` passed, including formatting and analysis,
  Rust core and FFI suites, 360 Dart core tests, 193 combined client/MCP
  authorization tests, 94 MCP tests, 96 benchmark tests, all generated and
  globally activated consumer smokes, 380 router tests, 13 focused native
  zero-copy tests, and Chrome/Dart2Wasm coverage.
- 2026-08-02: Commit `c68ddc5` was pushed to GitLab and GitHub. Exact-head
  GitHub CI `30724756945`, Dart Package Publish Dry Run `30724756944`, and WAMP
  Profile Benchmarks `30724756942` passed on their first attempts. CI uploaded
  coverage artifact `8826085925`, WAMP uploaded benchmark artifact
  `8826008381`, and the strict deployment-chain audit passed with a clean CI
  log scan and all required gates clean.

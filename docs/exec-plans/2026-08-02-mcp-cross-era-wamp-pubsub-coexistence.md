# Exec Plan: MCP Cross-Era WAMP Pub/Sub Coexistence

## Status

Active.

## Goal

Prove that router-hosted MCP direct JSON and compatibility-era Streamable HTTP
clients can hold separate logical subscriptions to the same declared WAMP
topic through one authorized router session, receive the same publication, and
release their ownership independently without interrupting the other consumer.

## Scope

- Add a native-router regression that keeps a sessionless direct JSON WAMP
  subscription active while the same public endpoint and principal initializes
  a Streamable HTTP session and subscribes to the same topic.
- Prove both logical handles receive one acknowledged self-delivered publish
  even when WAMP reuses one broker subscription ID for the router session.
- Prove direct JSON unsubscribe leaves the Streamable subscription usable, and
  Streamable unsubscribe or session deletion leaves the direct JSON
  subscription usable.
- Keep direct JSON free of MCP protocol session/resume state and prove final
  cleanup leaves no broker subscriber behind.
- Extend the isolated generated consumer package through the same public and
  bearer-protected lifecycle without private project assumptions.

## Non-Goals

- Add a new MCP protocol extension or change WAMP pub/sub wire formats.
- Merge direct JSON handle state into compatibility-era MCP session state.
- Add durable event replay, retained events, or cross-process subscription
  persistence.
- Change route authorization policy or caller-owned OAuth storage and refresh
  policy.

## Verification

- Focused native-router cross-era WAMP pub/sub regression.
- Consumer-package boundary tests.
- Isolated generated consumer package against the native router.
- `bin/test-fast` before and after the change.
- `bin/verify` before handoff.
- Exact-head GitHub CI, Dart package publish dry run, WAMP benchmark workflow,
  and strict deployment-chain audit after the implementation push.

## Progress

- 2026-08-02: Selected from `ROADMAP_NEXT.md` and `ROADMAP.md` as the next
  concrete MCP downstream-application readiness slice. Existing native and
  generated-consumer smokes prove direct JSON and Streamable WAMP pub/sub
  sequentially, but do not keep both logical subscriptions active on the same
  topic or prove cleanup independence when the router reuses one WAMP session.
- 2026-08-02: Pre-change `bin/test-fast` passed across package, native-client,
  live WAMP benchmark, public/global executable, and isolated consumer smokes.
- 2026-08-02: The focused native-router smoke now keeps a sessionless direct
  JSON handle and a Streamable handle on the same declared topic and physical
  WAMP subscription. Shared self-delivery, both cleanup orders, stable
  Streamable state, absent direct JSON session/resume state, and a final zero
  broker-subscriber count all pass. The first run exposed that WAMP lookup
  intentionally retains configured-topic metadata at zero subscribers, so the
  final assertion now uses the standard subscriber-count meta procedure.
- 2026-08-02: All 19 consumer-boundary tests pass. The isolated generated
  router CLI consumer analyzes cleanly and completes the same public and
  bearer-protected direct JSON/Streamable coexistence lifecycle against the
  native router without private project assumptions.
- 2026-08-02: Post-change `bin/test-fast` passed, including all 94 MCP tests,
  live WAMP transport and 96-case benchmark coverage, public and globally
  activated MCP consumers, the isolated consumer package, the generated
  router CLI consumer, and native router worker/runtime regressions.
- 2026-08-02: Full `bin/verify` passed formatting and analysis, Rust core and
  FFI suites, 360 core tests, all 94 MCP tests, the complete 193-case
  MCP/client authorization suite, Dart VM and Chrome/Dart2Wasm coverage, all
  generated and globally activated consumer smokes, all 96 benchmark tests,
  and the complete 380-case router suite. The implementation is ready to push;
  exact-head hosted workflows and the strict deployment-chain audit remain.

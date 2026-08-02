# Exec Plan: MCP Cross-Era WAMP Session-Delete Coexistence

## Status

Completed.

## Goal

Prove that deleting a router-hosted MCP Streamable HTTP session releases only
that endpoint's logical WAMP pub/sub ownership while a sessionless direct JSON
consumer on the same authorized router session remains usable.

## Scope

- Extend the native-router lifecycle regression so direct JSON and Streamable
  HTTP subscribe to one declared topic and share one physical WAMP
  subscription before the active Streamable session is deleted.
- Prove Streamable deletion cleans its resource and pub/sub ownership without
  creating or clearing direct JSON MCP session/resume state.
- Prove the direct JSON handle still receives an acknowledged self-delivered
  publication after deletion and final direct cleanup leaves zero broker
  subscribers.
- Extend the isolated generated consumer through active Streamable deletion,
  direct JSON survival, and a replacement Streamable session for public and
  bearer-protected routes without private project assumptions.

## Non-Goals

- Change MCP or WAMP wire formats, replay semantics, or route authorization.
- Persist logical subscription handles across deleted Streamable sessions.
- Merge direct JSON request state into compatibility-era Streamable sessions.
- Add a new public API when existing lifecycle operations are sufficient.

## Verification

- Focused native-router Streamable deletion regression.
- Consumer-package boundary tests.
- Isolated generated consumer package against the native router.
- `bin/test-fast` before and after the change.
- `bin/verify` before handoff.
- Exact-head GitHub CI, Dart package publish dry run, WAMP benchmark workflow,
  and strict deployment-chain audit after the implementation push.

## Progress

- 2026-08-02: Selected from `ROADMAP_NEXT.md` and `ROADMAP.md` as the next
  concrete MCP downstream-readiness slice. Existing coverage proves
  sole-owner Streamable deletion and explicit cross-era unsubscribe in both
  orders, but not deletion while the Streamable endpoint still shares a
  physical WAMP subscription with a sessionless direct JSON owner.
- 2026-08-02: Pre-change `bin/test-fast` passed across package, native-client,
  live WAMP benchmark, public/global executable, isolated consumer, generated
  router CLI consumer, and router worker/runtime coverage.
- 2026-08-02: The focused native-router regression passes with one sessionless
  direct JSON owner and one active Streamable owner sharing the same physical
  WAMP subscription. Streamable `DELETE` clears its resource subscription and
  MCP session/resume state while the broker subscriber count remains one; the
  direct handle then receives an acknowledged self-delivered publication and
  final direct cleanup reaches zero subscribers.
- 2026-08-02: All 19 consumer-boundary tests pass. The isolated generated
  router CLI consumer analyzes cleanly and completes active Streamable
  deletion, direct JSON survival, replacement-session rejoin on the same
  physical subscription, and independent final cleanup for public and
  bearer-protected routes.
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
- 2026-08-02: Commit `5e8b51d` was pushed to GitLab and GitHub. Exact-head
  GitHub CI `30733751981`, Dart Package Publish Dry Run `30733751980`, and WAMP
  Profile Benchmarks `30733751982` passed on their first attempts. CI uploaded
  coverage artifact `8828980789`, WAMP uploaded benchmark artifact
  `8828884780`, and the strict deployment-chain audit passed with a clean CI
  log scan and all required gates clean.

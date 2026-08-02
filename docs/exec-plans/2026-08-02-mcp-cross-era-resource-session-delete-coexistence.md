# Exec Plan: MCP Cross-Era Resource Session-Delete Coexistence

## Status

Completed.

## Goal

Prove that deleting a router-hosted MCP Streamable HTTP session releases only
that endpoint's dynamic-resource subscription ownership while an MCP
`2026-07-28` request-scoped listener on the same authorized router session
remains usable.

## Scope

- Extend the native-router deletion regression with a modern listener and an
  active Streamable subscription to the same configured dynamic resource.
- Prove Streamable deletion clears its protocol session and resource owner
  without interrupting the modern listener or creating modern session/resume
  state.
- Prove a replacement Streamable session can subscribe to the same resource,
  survive modern listener closure, and release the final broker subscriber.
- Extend the isolated generated consumer through the same lifecycle for public
  and bearer-protected routes without private project assumptions.

## Non-Goals

- Change MCP or WAMP wire formats, resource update payloads, or replay
  semantics.
- Persist compatibility-era resource subscriptions across deleted sessions.
- Merge request-scoped listener state into Streamable HTTP session state.
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
  concrete MCP downstream-readiness slice. Existing coverage proves explicit
  cross-era resource unsubscribe in both ownership orders and active
  Streamable deletion for WAMP pub/sub, but not deletion while a Streamable
  resource owner shares the physical WAMP subscription with a modern listener.
- 2026-08-02: Pre-change `bin/test-fast` passed across package, live WAMP,
  generated consumer, globally activated executable, and router fast coverage.
- 2026-08-02: The focused native-router regression now keeps a modern resource
  listener beside direct and Streamable WAMP owners, deletes the active
  Streamable session, proves the sessionless owners remain usable, creates a
  distinct replacement Streamable session, and reaches zero resource-update
  subscribers after independent cleanup. Modern SSE cancellation is observed
  by the router on the next bounded notification write, matching the existing
  request-scoped listener lifecycle; no production change was required.
- 2026-08-02: All 19 consumer-boundary tests pass. The isolated generated
  router CLI consumer analyzes cleanly and completes explicit unsubscribe,
  active Streamable deletion, modern-listener survival, replacement-session
  rejoin, and inverse final cleanup for public and bearer-protected routes. Its
  summary now exposes `resourceSubscriptionSessionDeleteCoexistence`.
- 2026-08-02: Post-change `bin/test-fast` passed, including all 94 MCP tests,
  live WAMP transport and 96-case benchmark coverage, public and globally
  activated MCP consumers, the isolated consumer package, the generated router
  CLI consumer, and native router worker/runtime regressions.
- 2026-08-02: Full `bin/verify` passed formatting and analysis, all 113 Rust
  core tests, all 52 Rust FFI tests, 360 Dart core tests, 94 MCP tests, the
  complete 193-case MCP/client authorization suite, all generated and globally
  activated consumer smokes, all 96 benchmark tests, the complete 380-case
  router suite, the 13-case native-handle follow-up, and Chrome/Dart2Wasm
  coverage. The implementation bundle is ready to push; exact-head hosted
  workflows and the strict deployment-chain audit remain.
- 2026-08-02: Commit `01a7654` was pushed to GitLab and GitHub. Exact-head
  GitHub CI `30736592378`, Dart Package Publish Dry Run `30736592418`, and WAMP
  Profile Benchmarks `30736592385` passed on their first attempts. CI uploaded
  coverage artifact `8829984781`, WAMP uploaded benchmark artifact
  `8829836979`, and the strict deployment-chain audit passed with a clean CI
  log scan and all required branch, workflow, package, publish-dry-run, and
  benchmark-artifact gates clean.

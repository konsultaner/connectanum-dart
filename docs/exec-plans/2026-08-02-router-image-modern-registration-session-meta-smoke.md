# Exec Plan: Router Image Modern Registration and Session Meta API Smoke

## Status

Completed.

## Goal

Make the canonical Router Image runtime evidence prove that a consumer can
discover, inspect, and invoke a router-provided WAMP procedure through modern
sessionless direct JSON and standard `tools/call` requests while session Meta
API results remain scoped to the current public or bearer-protected endpoint.

## Scope

- Declare `wamp.session.count` as a neutral router-provided procedure on the
  loaded image's public and protected MCP routes.
- Require `wamp.registration.match`, `wamp.registration.get`, and
  `wamp.session.count` in modern tool discovery.
- Match and inspect the declared procedure registration, including its id,
  URI, exact match policy, and single invocation policy.
- Invoke the procedure through direct JSON and standard `tools/call`, and
  require the session count to expose only the endpoint's current internal
  WAMP session.
- Run both call forms on public and bearer-protected endpoints, forwarding the
  router-issued grant on every protected request.
- Preserve the existing WAMP subscription Meta API, modern direct and standard
  pub/sub, compatibility-era Streamable HTTP, DELETE, authentication rejection,
  revocation, and session-isolation evidence.

## Non-Goals

- Add or change a WAMP Meta API procedure, MCP method, session model,
  authorization rule, topic, or application-owned WAMP callee.
- Expose sessions other than the current route endpoint's internal session.
- Publish or retag a router image.

## Verification

- Focused smoke-client source-contract, configuration, and behavioral tests.
- Real local native-router execution of the complete image smoke.
- `bin/test-fast` before and after the change.
- `bin/verify` before handoff.
- Exact-head CI, package dry run, WAMP benchmarks, Router Image dry run, and
  strict deployment-chain audit after the implementation push.

## Progress

- 2026-08-02: Selected after reviewing `docs/project_state.md`, both roadmaps,
  the completed Router Image plans, Serena memories, the loaded-image route
  configuration, and the router's registration/session Meta API symbols. The
  canonical image smoke proves subscription Meta API access but does not yet
  discover, inspect, and invoke a router-provided procedure or pin current
  session visibility through both modern call forms.
- 2026-08-02: Pre-change `bin/test-fast` passed. A focused regression then
  failed because the smoke client had no registration/session Meta API helper
  and the loaded configuration did not declare a callable procedure.
- 2026-08-02: Both public and protected routes now declare
  `wamp.session.count`. The smoke requires its registration and call tools,
  matches and inspects the exact/single registration, invokes the procedure,
  and requires `count: 1` through both sessionless direct JSON and standard
  `tools/call`. Every protected request forwards the router-issued bearer.
- 2026-08-02: All 13 focused Python tests, Python compilation, diff checks, and
  the complete public/protected smoke against a real local native router pass.
  Post-change `bin/test-fast` passes. Final `bin/verify` passes formatting,
  analysis, 113 Rust core tests, 52 Rust FFI tests, 360 Dart core tests, all 94
  MCP tests, the complete 193-case MCP/client suite, 96 benchmark tests, the
  complete 380-case router suite, the 13-case native follow-up, all generated
  and globally activated consumer smokes, and Chrome/Dart2Wasm. Commit, push,
  and exact-head hosted evidence remain.

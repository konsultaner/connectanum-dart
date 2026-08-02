# Exec Plan: Router Image Modern WAMP Meta API Smoke

## Status

Completed.

## Goal

Make the canonical Router Image runtime evidence prove that a consumer can
discover and inspect the router-provided WAMP subscription Meta API through
modern sessionless direct JSON and standard `tools/call` requests on both
public and bearer-protected endpoints.

## Scope

- Require `wamp.subscription.match` and `wamp.subscription.get` in the loaded
  image's modern tool catalog.
- Match the declared neutral topic and inspect the returned subscription
  details through direct JSON and standard `tools/call` requests.
- Send the required modern routing headers, keep every response sessionless,
  and forward the router-issued bearer grant on protected calls.
- Preserve modern direct and standard pub/sub, compatibility-era Streamable
  HTTP pub/sub and DELETE, authentication rejection, revocation, and session
  isolation evidence.
- Keep all fixtures free of private consumer assumptions.

## Non-Goals

- Add or change a WAMP Meta API procedure, MCP method, route option, topic,
  authentication method, or session model.
- Replace the deeper public Dart client and generated-consumer matrices.
- Publish or retag a router image.

## Verification

- Focused smoke-client source-contract and behavioral tests.
- Real local native-router execution of the complete image smoke.
- `bin/test-fast` before and after the change.
- `bin/verify` before handoff.
- Exact-head CI, package dry run, WAMP benchmarks, Router Image dry run, and
  strict deployment-chain audit after the implementation push.

## Progress

- 2026-08-02: Selected after reviewing `docs/project_state.md`, both roadmaps,
  the completed Router Image plans, Serena memories, and the router Meta API
  implementation. The loaded image advertises standard WAMP Meta API tools but
  does not invoke them in the canonical release smoke. Pre-change
  `bin/test-fast` passed.
- 2026-08-02: A focused behavioral regression first failed because the modern
  WAMP subscription Meta API helper was absent. The image smoke now requires
  `wamp.subscription.match` and `wamp.subscription.get`, matches the declared
  neutral topic, and validates the returned subscription id, URI, and exact
  match policy through both direct JSON methods and standard `tools/call` on
  public and bearer-protected endpoints.
- 2026-08-02: Twelve focused Python tests, Python compilation, the public
  artifact reference check, diff checks, and the complete image smoke against
  a real local native router pass. Post-change `bin/test-fast` passes the full
  fast regression matrix. Final `bin/verify` passes formatting, Rust core and
  FFI suites, all Dart suites, package/global consumer smokes, live WAMP
  workloads, and Chrome/Dart2Wasm. Commit, push, and exact-head hosted evidence
  remain pending.

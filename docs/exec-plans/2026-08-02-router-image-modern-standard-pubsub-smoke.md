# Exec Plan: Router Image Modern Standard Pub/Sub Smoke

## Status

In progress.

## Goal

Make the canonical Router Image runtime evidence prove that a standard MCP
application or agent can complete the router-provided pub/sub lifecycle through
modern sessionless `tools/call` requests on both public and bearer-protected
endpoints.

## Scope

- Subscribe, acknowledged publish, poll, and unsubscribe through modern
  `2026-07-28` `tools/call` requests for the declared neutral topic.
- Send the required `Mcp-Name` routing header for every operation.
- Keep every modern response free of MCP session state and forward the
  router-issued bearer grant on every protected request.
- Preserve modern direct-method pub/sub, standard metadata-tool invocation,
  compatibility-era Streamable HTTP pub/sub and DELETE, authentication
  rejection, revocation, and session-isolation evidence.
- Keep all fixtures free of private consumer assumptions.

## Non-Goals

- Add or change an MCP method, tool, topic, authentication method, or session
  model.
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

- 2026-08-02: Selected after reviewing `docs/project_state.md`,
  `ROADMAP_NEXT.md`, and the MCP readiness section of `ROADMAP.md`. The loaded
  image already proves modern standard metadata-tool invocation, direct-method
  pub/sub, and compatibility-era standard-tool pub/sub, but not modern standard
  pub/sub through `tools/call`.
- 2026-08-02: Pre-change `bin/test-fast` passed. A source-contract regression
  and focused behavior test then failed because the standard modern pub/sub
  helper and public/protected calls were absent.
- 2026-08-02: The smoke now completes subscribe, acknowledged publish, event
  poll, and unsubscribe through modern sessionless `tools/call` requests on
  public and bearer-protected routes. Eleven focused Python tests, Python
  compilation, diff checks, and the complete smoke against a real local native
  router pass. Post-change `bin/test-fast` also passes, including the complete
  MCP/client, live WAMP, and consumer-package regression matrix. Final local
  `bin/verify` passes formatting, Rust core and FFI suites, all Dart suites,
  package/global consumer smokes, live WAMP workloads, and Chrome/Dart2Wasm.
  Commit, push, and exact-head hosted evidence remain pending.

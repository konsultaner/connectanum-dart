# Exec Plan: Router Image Standard Tool-Call Smoke

## Status

Completed.

## Goal

Make the canonical Router Image runtime evidence prove that a standard MCP
application or agent can invoke router-provided tools through `tools/call` on
both modern sessionless direct JSON and compatibility-era Streamable HTTP
paths, for public and bearer-protected endpoints.

## Scope

- Add a modern MCP `2026-07-28` `tools/call` request for the router-provided
  `connectanum.api.list` tool on public and protected routes.
- Keep that modern request sessionless and forward the router-issued bearer
  grant on every protected call.
- Drive the compatibility-era subscribe, acknowledged publish, event poll,
  and unsubscribe lifecycle through standard `tools/call` envelopes instead
  of relying only on Connectanum custom method dispatch.
- Preserve modern direct-method pub/sub, discovery, authentication rejection,
  revocation, Streamable initialization/DELETE, and session-header isolation.
- Keep all checked-in fixtures neutral and free of private consumer assumptions.

## Non-Goals

- Add or change an MCP method, tool, topic, authentication method, or session
  model.
- Add an external application procedure to the image fixture.
- Replace the deeper generated-consumer and public Dart client matrices.
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
  image already proves standard tool discovery, modern direct Connectanum
  methods, and compatibility-era session lifecycle, but not standard
  `tools/call` execution across both protocol eras and auth profiles.
- 2026-08-02: Pre-change `bin/test-fast` passed. New source-contract and
  behavioral regressions then failed on the absent modern standard tool call
  and the compatibility pub/sub lifecycle's custom-method envelopes.
- 2026-08-02: The smoke now executes `connectanum.api.list` through modern
  sessionless `tools/call` for public and bearer-protected endpoints, including
  the required `Mcp-Name` routing header, and executes compatibility subscribe,
  publish, poll, and unsubscribe through standard `tools/call` envelopes.
  Ten focused Python tests, Python compilation, diff checks, and the full
  public/protected smoke against a real local native router pass.
- 2026-08-02: Post-change `bin/test-fast` passes, including all generated
  consumer boundaries, 360 core tests, 94 MCP tests, 193 client/MCP tests,
  96 benchmark tests, real-router workloads, and standalone/global consumer
  package smokes.
- 2026-08-02: Final `bin/verify` passes workspace formatting, the complete
  Rust and Dart suites, 380 router tests, focused native zero-copy coverage,
  real-router benchmarks, standalone/global package smokes, and
  Chrome/Dart2Wasm transport coverage.
- 2026-08-02: Commit `c6540ea` was pushed to GitLab and GitHub. Exact-head CI
  `30752149679`, Dart Package Publish Dry Run `30752167176`, WAMP Profile
  Benchmarks `30752167162`, and Router Image dry run `30752167017` all passed.
  CI uploaded coverage artifact `8834989571`, WAMP uploaded benchmark artifact
  `8834871502`, and Router Image uploaded preview artifact `8834785297`. The
  comprehensive strict deployment-chain audit exited clean with exact-head CI
  and log cleanliness, standard public and protected `tools/call` loaded-image
  smoke, multi-architecture image build, skipped GHCR login, and all required
  package, benchmark, workflow-visibility, branch-protection, and
  public-router-package gates clean.

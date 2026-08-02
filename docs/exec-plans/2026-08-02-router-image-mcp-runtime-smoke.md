# Exec Plan: Router Image MCP Runtime Smoke

## Status

In progress.

## Goal

Make router-image release evidence prove that the built container can start a
neutral router-hosted MCP endpoint and serve a downstream application without
source-checkout runtime assumptions.

## Scope

- Add a neutral container smoke configuration with a public router-hosted MCP
  route and explicitly declared WAMP pub/sub topic.
- Add a reusable black-box smoke runner that starts a supplied local image and
  proves MCP `2026-07-28` discovery/direct JSON behavior plus compatibility-era
  Streamable initialization, pub/sub, and DELETE cleanup.
- Run that smoke on a locally loaded Linux image before every Router Image
  dry run or publish build.
- Make the deployment-chain audit reject Router Image evidence that lacks the
  runtime smoke step.

## Non-Goals

- Publish or retag a router image.
- Add MCP protocol methods, change router endpoint behavior, or introduce a
  new authentication policy.
- Duplicate the exhaustive source/global-activation consumer matrix inside the
  container workflow.
- Depend on private application names, paths, services, or credentials.

## Verification

- Focused smoke-runner and deployment-audit regression tests.
- Local native-architecture Docker build and black-box MCP runtime smoke.
- `bin/test-fast` before and after the change.
- `bin/verify` before handoff.
- Exact-head GitHub CI, Dart package dry run, WAMP profile benchmarks, Router
  Image dry run, and strict deployment-chain audit after the implementation
  push.

## Progress

- 2026-08-02: Selected after comparing `ROADMAP_NEXT.md` and `ROADMAP.md`.
  Router-hosted MCP functionality and source/global-activation consumers are
  mature, but the latest Router Image dry run predates the accumulated MCP
  production inputs and validates only image construction/metadata, not an MCP
  request through the built artifact.
- 2026-08-02: Pre-change `bin/test-fast` passed across deployment/package
  contracts, 360 core tests, 94 MCP tests, the complete 193-case MCP/client
  authorization suite, 96 benchmark tests with live WAMP coverage, generated
  consumer packages, globally activated executables, and router fast tests.
- 2026-08-02: Added the neutral `image.smoke` container configuration, a
  reusable image runner, and a black-box Python client. The client proves
  stateless `2026-07-28` discovery, direct tool/meta API access, then a
  `2025-11-25` Streamable session with initialized notification,
  subscribe/publish/poll/unsubscribe, and DELETE teardown.
- 2026-08-02: The Router Image workflow now builds and loads a Linux/amd64
  smoke image before the release build. The deployment audit requires both the
  local image build and the successful MCP runtime step; its 22 regressions and
  all 5 smoke-runner regressions pass.
- 2026-08-02: Docker registry metadata resolution stalled locally before the
  canonical Dockerfile could resolve uncached Rust and Debian bases. A current
  Linux Dart AOT router was therefore packaged over a cached router runtime for
  the native-architecture check; the black-box MCP smoke passed. The exact-base
  and multi-architecture proof remains assigned to the required hosted Router
  Image dry run.
- 2026-08-02: Post-change `bin/test-fast` passed. Full `bin/verify` passed with
  no formatting changes, 113 Rust core tests, 52 Rust FFI tests, 360 Dart core
  tests, all 94 MCP tests, the complete 193-case MCP/client suite, all 96
  benchmark tests with live WAMP workloads, isolated and globally activated
  consumers, the complete 380-case router suite, 13 focused native follow-ups,
  and Chrome/Dart2Wasm WebSocket coverage. The implementation is ready to push;
  exact-head hosted CI, package, WAMP, Router Image, and audit evidence remain.

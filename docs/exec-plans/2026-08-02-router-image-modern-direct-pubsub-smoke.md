# Exec Plan: Router Image Modern Direct Pub/Sub Smoke

## Status

Completed.

## Goal

Make the canonical Router Image runtime evidence prove that the packaged router
supports a complete MCP `2026-07-28` sessionless direct-JSON pub/sub lifecycle
on both public and bearer-protected endpoints, alongside the existing
compatibility-era Streamable HTTP lifecycle.

## Scope

- Extend the black-box image client through direct subscribe, acknowledged
  publish, event poll, and unsubscribe operations on the declared neutral topic.
- Run the lifecycle against both public and router-issued bearer-protected MCP
  routes.
- Require every modern direct response to remain sessionless and keep the
  existing discovery, direct meta, Streamable initialization/pub/sub/DELETE,
  auth rejection, and revocation evidence intact.
- Keep the smoke self-contained and free of private consumer assumptions.

## Non-Goals

- Add a new MCP protocol extension, topic, authentication method, or session
  model.
- Duplicate the complete generated-consumer coexistence matrix in the image
  workflow.
- Publish or retag a router image.

## Verification

- Focused smoke-client contract tests and Python compilation.
- `bin/test-fast` before and after the change.
- `bin/verify` before handoff.
- Exact-head GitHub CI, package dry run, WAMP benchmarks, Router Image dry run,
  and strict deployment-chain audit after the implementation push.

## Progress

- 2026-08-02: Selected after reviewing `docs/project_state.md`,
  `ROADMAP_NEXT.md`, and `ROADMAP.md`. Public package and native-router evidence
  already cover lifecycle-free direct WAMP helpers, but the canonical loaded
  Router Image smoke stops at modern direct meta access and compatibility-era
  Streamable pub/sub.
- 2026-08-02: Pre-change `bin/test-fast` passed across analysis, deployment and
  package contracts, 360 core tests, 94 MCP tests, the 193-case MCP/client
  suite, all 96 benchmark tests with live WAMP workloads, generated and globally
  activated consumers, and router auth/session coverage.
- 2026-08-02: Added a failing source-contract regression that identified the
  absent public and protected modern direct-pub/sub image paths, then added a
  behavioral regression proving the protected lifecycle uses the modern helper
  with its bearer grant on every request.
- 2026-08-02: The black-box client now completes sessionless direct subscribe,
  acknowledged publish, event poll, and unsubscribe operations before each
  route's compatibility-era Streamable lifecycle. The real local native router
  passed the complete public and protected smoke.
- 2026-08-02: Seven focused Python tests, Python compilation, shell syntax,
  diff checks, and the public-artifact privacy guard passed. Post-change
  `bin/test-fast` passed across the complete fast verification matrix.
- 2026-08-02: Final `bin/verify` passed formatting, the complete Rust and Dart
  test matrices, native and browser transport coverage, real-router benchmark
  workloads, and standalone/global consumer package smokes. At that point,
  exact-head hosted Router Image and deployment-chain evidence remained before
  completion.
- 2026-08-02: Commit `8060384` was pushed to GitLab and GitHub. Exact-head CI
  `30748535720`, Dart Package Publish Dry Run `30749188442`, WAMP Profile
  Benchmarks `30749188358`, and Router Image dry run `30749188366` all passed.
  CI uploaded coverage artifact `8833861813`, WAMP uploaded benchmark artifact
  `8833949873`, and Router Image uploaded preview artifact `8833873924`. The
  strict deployment-chain audit exited clean with exact-head relevance, clean
  CI logs, the public and protected modern direct-pub/sub loaded-image smoke,
  multi-architecture image build, skipped GHCR login, and all required package,
  benchmark, workflow-visibility, branch-protection, and public-router-package
  gates clean.

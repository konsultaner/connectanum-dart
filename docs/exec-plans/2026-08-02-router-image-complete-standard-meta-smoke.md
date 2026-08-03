# Exec Plan: Router Image Complete Standard Meta API Smoke

## Status

Completed.

## Goal

Make the canonical loaded Router Image evidence exercise every standard WAMP
registration, subscription, and session Meta API procedure that the router
exposes through modern MCP direct JSON and standard `tools/call` requests on
both public and bearer-protected endpoints.

## Scope

- Require the remaining registration and subscription Meta API tools in modern
  discovery: list, lookup, member listing, and member count.
- Extend configured registration coverage to list and look up the configured
  procedure, then prove that its synthetic Router Image registration has no
  live callees.
- Extend configured subscription coverage to list and look up the configured
  topic, then prove that its synthetic Router Image subscription has no live
  subscribers.
- Exercise every added check through both modern direct JSON and standard
  `tools/call` on public and protected routes.
- Forward the router-issued bearer on every protected request.
- Preserve the existing registration/session identity, pub/sub, compatibility
  Streamable HTTP, DELETE, authentication, revocation, and isolation evidence.

## Non-Goals

- Change router Meta API behavior, configured route snapshots, WAMP session
  lifecycle, authentication, authorization, or MCP protocol semantics.
- Add live WAMP callees or subscribers to the packaged image smoke.
- Publish or retag a router image.

## Verification

- Focused smoke-client source-contract and behavioral tests, with a reproduced
  regression before implementation.
- Real local native-router execution of the complete image smoke.
- `bin/test-fast` before and after the change.
- `bin/verify` before handoff.
- Exact-head CI, package dry run, WAMP benchmarks, Router Image dry run, and
  strict deployment-chain audit after the implementation push.

## Progress

- 2026-08-02: Selected after reviewing `docs/project_state.md`, both roadmaps,
  the completed Router Image plans, Serena memories, and the router Meta API
  implementation. The runtime already exposes all 15 standard session,
  registration, and subscription procedures, but the canonical loaded-image
  smoke invokes only seven of them.
- 2026-08-02: Pre-change `bin/test-fast` passed at exact local, GitLab, and
  GitHub head `0c736f4`, including native/router integration, MCP/client,
  benchmark, packaging, generated consumer, globally activated CLI consumer,
  and focused router suites.
- 2026-08-02: Focused regressions first failed because the image helpers did
  not invoke the remaining eight configured registration/subscription Meta API
  procedures. The smoke now requires those tools in discovery and validates
  list, lookup, zero-member list, and zero-member count responses through both
  modern call forms while preserving authorization headers.
- 2026-08-02: All 13 focused Python tests, Python compilation, and the complete
  public/protected smoke against a real local native router passed. Post-change
  `bin/test-fast` also passed, including the complete Dart, native/router,
  MCP/client, benchmark, packaging, generated consumer, and globally activated
  Router CLI consumer suites.
- 2026-08-02: Final local `bin/verify` passed formatting and analysis, 113 Rust
  core tests, 52 Rust FFI tests, 360 Dart core tests, all 94 MCP tests, the
  complete 193-case MCP/client suite, all 96 benchmark tests, the complete
  380-case router suite, the 13-case native follow-up, all generated and
  globally activated consumer smokes, and Chrome/Dart2Wasm.
- 2026-08-02: Commit `459a16b` was pushed to GitLab and GitHub. Exact-head CI
  `30770494000`, Dart Package Publish Dry Run `30771153289`, WAMP Profile
  Benchmarks `30771153291`, and Router Image dry run `30771153281` all passed.
  CI uploaded coverage artifact `8840554942`, WAMP uploaded benchmark artifact
  `8840642436`, and Router Image uploaded preview artifact `8840564135`. The
  comprehensive strict deployment-chain audit exited clean with exact-head CI
  and log cleanliness, the loaded-image complete standard Meta API smoke,
  multi-architecture image build, skipped GHCR login, and all required package,
  native-release, benchmark, workflow-visibility, branch-protection, and
  public-router-package gates clean. Selecting a later RC tag remains an
  approval-gated release action outside this checkpoint.

# Exec Plan: Router Image Modern Session Identity Meta API Smoke

## Status

Completed.

## Goal

Make the canonical Router Image runtime evidence prove that modern sessionless
direct JSON and standard `tools/call` requests can list the route-local WAMP
session and inspect its authorization identity on both public and
bearer-protected MCP endpoints.

## Scope

- Require `wamp.session.list` and `wamp.session.get` in modern tool discovery.
- Extend the existing registration/session Meta API smoke through both modern
  direct JSON and standard `tools/call`.
- Require every session listing to contain exactly one route-local session.
- Require session details to preserve the returned id and expose anonymous
  identity on the public route.
- Require session details to expose the router-issued ticket identity and
  member role on the protected route.
- Forward the router-issued bearer on every protected request.
- Preserve the existing registration/subscription Meta API, modern direct and
  standard pub/sub, compatibility-era Streamable HTTP, DELETE, authentication
  rejection, revocation, and session-isolation evidence.

## Non-Goals

- Change router session visibility, WAMP Meta API behavior, authentication,
  authorization, or MCP protocol semantics.
- Expose any session other than the current route endpoint's internal session.
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
  the completed Router Image plans, Serena memories, the image smoke client,
  and router session Meta API symbols. The packaged smoke counts the one
  visible route-local session but does not yet list it or inspect its
  public/protected authorization identity through both modern call forms.
- 2026-08-02: Pre-change `bin/test-fast` passed at exact local, GitLab, and
  GitHub head `dd4c118`.
- 2026-08-02: A focused regression first failed because the modern Meta API
  smoke helper did not accept expected session identity or invoke
  `wamp.session.list/get`. The helper now requires exactly one listed
  route-local session, retrieves its details through both direct JSON and
  standard `tools/call`, and validates the public anonymous identity or the
  protected ticket identity and member role.
- 2026-08-02: All 13 focused Python tests, Python compilation, and the complete
  public/protected smoke against a real local native router passed. Post-change
  `bin/test-fast` also passed, including the complete Dart, native/router,
  MCP/client, benchmark, packaging, consumer, and focused router suites.
- 2026-08-02: Final local `bin/verify` passed formatting, analysis, 113 Rust
  core tests, 52 Rust FFI tests, 360 Dart core tests, all 94 MCP tests, the
  complete 193-case MCP/client suite, all 96 benchmark tests, the complete
  380-case router suite, the 13-case native follow-up, all generated and
  globally activated consumer smokes, and Chrome/Dart2Wasm. Commit, push, and
  exact-head hosted evidence remain.
- 2026-08-02: Commit `0c736f4` was pushed to GitLab and GitHub. Exact-head CI
  `30766784326`, Dart Package Publish Dry Run `30767521465`, WAMP Profile
  Benchmarks `30767522244`, and Router Image dry run `30767523222` all passed.
  CI uploaded coverage artifact `8839408642`, WAMP uploaded benchmark artifact
  `8839511593`, and Router Image uploaded preview artifact `8839425199`. The
  comprehensive strict deployment-chain audit exited clean with exact-head CI
  and log cleanliness, the loaded-image session-identity Meta API smoke,
  multi-architecture image build, skipped GHCR login, and every required
  package, native-release, benchmark, workflow-visibility, branch-protection,
  and public-router-package gate clean. Selecting a later RC tag remains an
  approval-gated release action outside this checkpoint.

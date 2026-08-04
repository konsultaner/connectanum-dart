# Exec Plan: Router Image JSON-Response Stateless Package Smoke

## Status

Completed.

## Goal

Prove that a consumer using the globally activated public MCP package can use
the canonical Router Image's protected JSON-response endpoint with the modern
stateless protocol, router-issued authentication, direct JSON and WAMP Meta
APIs, pub/sub, and request-scoped resource updates without repository-private
assumptions.

## Scope

- Run the modern `2026-07-28` package-client lifecycle against
  `/mcp/secure-json` in addition to the existing protected default route.
- Require the JSON-response route to complete router-issued grant refresh and
  revocation checks while remaining protocol-sessionless.
- Require direct JSON tools, configured resources/prompts, WAMP metadata,
  pub/sub, and request-scoped resource-update notifications on that route.
- Emit one additional bounded package evidence line identifying stateless JSON
  POST responses for hosted log inspection.

## Non-Goals

- Change router MCP response transport semantics or public package APIs.
- Add another protocol version, endpoint, authentication method, or resource.
- Duplicate the raw compatibility session/delete checks already maintained for
  the same JSON-response endpoint.

## Verification

- Pre-change `bin/test-fast`.
- Focused fail-first Router Image contract for the missing stateless
  JSON-response package invocation.
- Python compilation, shell syntax validation, and the complete Router Image
  contract suite.
- The complete runner against a current-source local image when available.
- Full `bin/verify` before handoff.
- Exact-head CI and Router Image dry run, hosted evidence inspection, and the
  comprehensive strict deployment-chain audit after the implementation push.

## Progress

- 2026-08-04: Selected after the canonical image gained protected
  compatibility JSON-response coverage but still ran the modern package client
  only against the default public and protected response routes. Both roadmaps
  keep speculative transport work paused and prioritize concrete downstream MCP
  usability and deployment evidence.
- 2026-08-04: Pre-change `bin/test-fast` passed the complete fast regression
  set, including isolated and globally activated consumer smokes, Router Image
  contracts, MCP authorization coverage, and live WAMP benchmark workloads.
- 2026-08-04: The focused contract failed first because the runner contained
  only three authenticated package lifecycles and no stateless invocation for
  the protected JSON-response endpoint.
- 2026-08-04: The stateless package helper now applies protected auth lifecycle
  assertions to route variants, identifies JSON POST response evidence, and
  runs the globally activated client against `/mcp/secure-json`. Python
  compilation, shell syntax validation, and all 27 Router Image contracts pass.
  The complete loaded-image runner also passes against the newest verified
  source-equivalent local router binary and emits exactly six bounded package
  evidence lines. The new line proves modern sessionless behavior,
  router-issued auth refresh/revocation, a refreshed request-scoped resource
  listener, direct JSON/meta/pub-sub coverage, and `post_response=json`.
- 2026-08-04: Full `bin/verify` passed formatting, all Rust and FFI suites, 360
  core tests, 94 MCP tests, the complete 193-case MCP/client authorization
  suite, all 96 benchmark tests with 36 live real-router WAMP workloads, every
  isolated and globally activated consumer smoke, the complete 380-case router
  suite, 13 native-forwarding follow-ups, and Chrome/Dart2Wasm coverage.
- 2026-08-04: Implementation commit `d779ce5` was pushed to GitLab and GitHub.
  Exact-head CI `30874512855` passed Fast Checks, Full Verify, Dart VM Coverage,
  Codecov upload, zero check annotations, and coverage artifact `8879349824`.
  Router Image dry run `30874549110` passed its canonical Linux/amd64
  current-source build, loaded-image runtime smoke, non-publishing
  multi-architecture build, skipped GHCR login, zero check annotations, and
  uploaded preview artifact `8879056488`. Its hosted log retains the raw
  compatibility JSON-response marker and contains exactly six package evidence
  lines. The new protected JSON-response stateless line proves protocol
  `2026-07-28`, router-issued auth and refreshed listener lifecycle, sessionless
  direct JSON/meta/pub-sub coverage, and `post_response=json`. Both masters
  resolve to the exact implementation commit, and the comprehensive strict
  deployment-chain audit exited zero with every required gate ready; RC tagging
  and prerelease creation remain separate approval-gated release actions.

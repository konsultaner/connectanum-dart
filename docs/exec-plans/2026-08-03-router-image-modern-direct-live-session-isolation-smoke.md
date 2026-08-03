# Exec Plan: Router Image Modern Direct Live-Session Isolation Smoke

## Status

Completed.

## Goal

Prove that router-hosted MCP `2026-07-28` standard and Connectanum direct JSON
requests both ignore a live compatibility-era `MCP-Session-Id` without
accessing or mutating the referenced `2025-11-25` Streamable HTTP session.

## Scope

- Create a real compatibility Streamable session and pub/sub subscription on
  each public and bearer-protected Router Image endpoint.
- Send both a modern standard `tools/call` poll and a modern direct
  `connectanum.pubsub.poll` request carrying that live compatibility session
  ID.
- Require both modern requests to remain sessionless, return the expected
  unknown subscription-handle tool error, and never echo `MCP-Session-Id`.
- Continue the compatibility session through publish, poll, unsubscribe, and
  DELETE so the smoke proves neither modern request mutated its state.
- Emit one bounded hosted-log marker that distinguishes direct and standard
  cross-era isolation for public and protected routes.

## Non-Goals

- Change the protocol-era routing behavior already implemented by the router.
- Permit modern clients to use compatibility sessions.
- Add another MCP protocol extension or compatibility-session mechanism.

## Verification

- Pre-change `bin/test-fast`.
- Focused Router Image smoke-contract tests, including a failing direct JSON
  contract before implementation.
- The complete real Router Image runner against a freshly built image.
- Full `bin/verify` before handoff.
- Exact-head CI and Router Image dry run, relevant package/native/WAMP
  evidence, hosted log inspection, and the comprehensive strict
  deployment-chain audit after the implementation push.

## Progress

- 2026-08-03: Selected after the standard `tools/call` loaded-image smoke
  proved live compatibility-session isolation but left the shipped direct JSON
  tool/meta API path unproven. Both protocol paths use the same modern
  sessionless router endpoint, so the next release-evidence boundary is to
  exercise them against the same real compatibility subscription and preserve
  its complete lifecycle.
- 2026-08-03: Pre-change `bin/test-fast` passed, including the focused Router
  Image contracts, all MCP and client authorization tests, live WAMP benchmark
  workloads, and isolated plus globally activated consumer smokes.
- 2026-08-03: The focused regression failed first because the live-session
  helper issued only the standard `tools/call` probe. It now issues standard
  and direct JSON polls with distinct modern request metadata, requires the
  same unknown-handle error from both, and then leaves the compatibility
  lifecycle unchanged. Python compilation, the focused regression, all 19
  Router Image contracts, and the complete runner against a freshly built
  Linux/amd64 image pass. The bounded raw evidence reports
  `modern_live_session_ignored=true standard=true direct=true` for public and
  protected routes. Full `bin/verify` also passed, including formatting, all
  Rust/FFI suites, the updated 19-test Router Image contract, 360 core tests,
  all 94 MCP tests, the complete 193-case MCP/client authorization suite, all
  96 benchmark tests with live WAMP workloads, every isolated and globally
  activated consumer smoke, the complete 380-case router suite, 13 focused
  native-forwarding tests, and Chrome/Dart2Wasm coverage.
- 2026-08-03: Implementation commit `7ca40a5` was pushed to GitLab and GitHub.
  Exact-head CI `30845561001` passed Fast Checks, Dart VM Coverage, Full
  Verify, Codecov upload, and coverage artifact `8869020588`. Router Image dry
  run `30845587286` passed the loaded-image runtime smoke and uploaded preview
  artifact `8868540607`; its log contains the bounded
  `modern_live_session_ignored=true standard=true direct=true` marker plus
  exactly four public/protected package evidence lines. The latest package
  publish dry run, native release dry run, and WAMP profile benchmark remain
  relevant because no sensitive inputs changed. The comprehensive strict
  deployment-chain audit exited zero with every required gate clean.

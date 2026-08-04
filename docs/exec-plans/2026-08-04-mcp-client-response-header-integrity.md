# Exec Plan: MCP Client Response Header Integrity

## Status

Completed.

## Goal

Make every public standard Streamable HTTP lifecycle path validate response
protocol and session metadata consistently, without turning direct JSON helpers
into session-aware operations.

## Scope

- Require modern stateless standard POST responses to echo the requested
  protocol version when they emit `MCP-Protocol-Version`.
- Reject `MCP-Session-Id` on modern stateless standard POST responses before
  returning a result or changing client state.
- Apply the same protocol-version and sessionless checks to successful
  `subscriptions/listen` response headers before creating a listener.
- Require compatibility-era DELETE response protocol echoes, when present, to
  match the active protocol version before clearing local session state.
- Preserve compatibility POST/GET session semantics and keep direct JSON
  response headers lifecycle-free.

## Non-Goals

- Make optional response protocol-version headers mandatory.
- Change router protocol negotiation or session creation rules.
- Validate or adopt lifecycle headers from direct JSON helpers.
- Add new MCP protocol versions or endpoint capabilities.

## Verification

- Pre-change `bin/test-fast`.
- Fail-first public-client regressions for modern standard POST session/version
  headers, modern listener session/version headers, and DELETE version drift.
- Focused client analysis and Streamable HTTP client tests.
- Generated client-only consumer-package smoke.
- Full `bin/verify` before handoff.
- Exact-head hosted workflows and strict deployment-chain audit after push.

## Progress

- 2026-08-04: Selected after protocol-negotiation integrity. Compatibility
  POST and GET/SSE responses validate active session and protocol echoes, but
  modern standard POST bypasses that shared path, modern listeners check only
  for a session header, and DELETE checks only the session echo. Direct JSON
  intentionally remains lifecycle-free.
- 2026-08-04: Exact local, GitLab, and GitHub head `906902c` began from a
  green full verification and hosted deployment chain. Focused fail-first
  coverage then reproduced all three remaining gaps: modern standard POST
  accepted a response session, modern `subscriptions/listen` accepted a
  mismatched protocol echo, and compatibility DELETE accepted a mismatched
  protocol echo.
- 2026-08-04: Standard Streamable POST now separates response-header
  validation from session-state mutation. Modern stateless requests reject
  response sessions and validate optional protocol echoes while preserving an
  unrelated compatibility session. Request-scoped listeners use the same
  validation before exposure, compatibility DELETE validates before cleanup,
  and direct JSON remains lifecycle-free.
- 2026-08-04: Focused client analysis and all 128 Streamable HTTP client tests
  pass. Post-change `bin/test-fast` and final `bin/verify` pass. Final
  verification covers 113 Rust core and 52 Rust FFI tests, 360 Dart core
  tests, 94 MCP tests, the complete 208-case MCP/client authorization suite,
  all 96 benchmark tests, all 384 router tests, native and Chrome/Dart2Wasm
  follow-ups, and every isolated and globally activated consumer/CLI smoke.
- 2026-08-04: Implementation commit `1420c0d` is on both maintained `master`
  branches. Exact-head CI `30931583546`, Dart Package Publish Dry Run
  `30931583530`, WAMP Profile Benchmarks `30931586035`, and Router Image dry
  run `30933114054` all passed on their first attempts. Coverage artifact
  `8901921112`, WAMP artifact `8901505282`, Router Image preview artifact
  `8901965043`, and Docker build records `8902067169` and `8902066706` were
  uploaded. The comprehensive strict deployment-chain audit passes with clean
  exact-head CI logs, loaded-image MCP runtime smoke, multi-architecture image
  build, and all required branch, workflow, package, native-release,
  publish-dry-run, and benchmark gates clean. Its non-gating release-candidate
  summary remains intentionally not ready because no approved RC tag points at
  this implementation commit.

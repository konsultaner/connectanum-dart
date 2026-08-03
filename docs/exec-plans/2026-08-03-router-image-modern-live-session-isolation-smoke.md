# Exec Plan: Router Image Modern Live-Session Isolation Smoke

## Status

Completed.

## Goal

Prove that router-hosted MCP `2026-07-28` requests ignore compatibility-era
`MCP-Session-Id` headers without accessing, mutating, or deleting the referenced
live `2025-11-25` Streamable HTTP session.

## Scope

- Create a real compatibility Streamable session and pub/sub subscription on
  each public and bearer-protected Router Image endpoint.
- Send a modern standard `tools/call` pub/sub poll carrying that live
  compatibility session ID.
- Require the modern request to remain sessionless, return the expected unknown
  subscription-handle tool error, and never echo `MCP-Session-Id`.
- Continue the compatibility session through publish, poll, unsubscribe, and
  DELETE so the smoke proves the modern request did not mutate its state.
- Emit one bounded hosted-log marker for the public/protected cross-era result.

## Non-Goals

- Change the protocol-era routing behavior already implemented by the router.
- Permit modern clients to use compatibility sessions.
- Add another MCP protocol extension or session mechanism.

## Verification

- Pre-change `bin/test-fast`.
- Focused Router Image smoke-contract tests.
- The complete real Router Image runner against a locally built image.
- Full `bin/verify` before handoff.
- Exact-head CI, package dry run, Router Image dry run, WAMP benchmarks, hosted
  log inspection, and the comprehensive strict deployment-chain audit after
  the implementation push.

## Progress

- 2026-08-03: Selected after confirming the MCP `2026-07-28` Streamable HTTP
  specification explicitly requires servers to ignore `MCP-Session-Id` and not
  mint or echo session IDs, while current release evidence proves only normal
  sessionless clients and unknown stale compatibility identifiers. The router
  already separates sessionless and compatibility endpoint keys, but no
  loaded-image smoke proves that a modern request carrying an actual live
  compatibility session ID cannot reach or disturb that session.
- 2026-08-03: Pre-change `bin/test-fast` passed.
- 2026-08-03: The canonical raw image probe now creates a compatibility
  subscription, attempts to poll it through a modern standard tool call carrying
  the live session ID, requires the unknown-handle tool error with no response
  session header, and then completes compatibility publish, poll, unsubscribe,
  and DELETE. The focused 19-test Router Image contract passes, as does the
  complete runner against a fresh local amd64 image for public and protected
  routes. Full `bin/verify` also passed, including formatting, Rust/FFI, the
  updated 19-test Router Image contract, package and consumer smokes, live WAMP
  integration, the complete router suite, HTTP/2 and HTTP/3 integration, and
  the Chrome/Dart2Wasm browser smoke.
- 2026-08-03: Implementation commit `8cbf618` was pushed to GitLab and GitHub.
  Exact-head CI `30839813099` passed Fast Checks, Dart VM Coverage, Full
  Verify, the clean hosted-log scan, Codecov upload, and coverage artifact
  `8866796076`. Router Image dry run `30839831715` passed the loaded-image
  runtime smoke and uploaded preview artifact `8866312222`; its exact-head log
  contains the bounded modern-live-session isolation marker plus exactly four
  public/protected package evidence lines. The latest package publish dry run,
  native release dry run, and WAMP profile benchmark remain relevant because
  no sensitive inputs changed. The comprehensive strict deployment-chain audit
  exited zero with every required gate clean.

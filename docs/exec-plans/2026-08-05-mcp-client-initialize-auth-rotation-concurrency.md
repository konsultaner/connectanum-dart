# Exec Plan: MCP Client Initialize Auth-Rotation Concurrency

## Status

Completed.

## Goal

Prevent delayed rejected or malformed compatibility `initialize` responses
issued under a replaced bearer credential from clearing the active MCP
Streamable HTTP session and resume cursor.

## Scope

- Carry the request's captured authorization generation into initialize
  response-state handling.
- Require both session and authorization ownership before a rejected or
  malformed initialize response can clear compatibility state.
- Keep successful initialize response handling session-authoritative so
  proactive same-principal refresh can complete in flight.
- Keep HTTP 404 cleanup session-authoritative and retain rejected grant
  replacement semantics.
- Prove the public behavior through focused client regressions and the neutral
  generated client-only consumer package.

## Non-Goals

- Serialize concurrent requests during credential replacement.
- Infer whether two independently issued bearer grants represent one
  principal.
- Change successful initialize negotiation or HTTP 401/404 behavior.
- Add automatic refresh scheduling or request retry.

## Verification

- Pre-change `bin/test-fast`.
- Fail-first regressions for delayed JSON-RPC initialize rejection and
  malformed initialize response after validated grant replacement.
- Control regressions for successful in-flight initialize and rejected grant
  replacement.
- Focused client analysis and Streamable HTTP client tests.
- Generated client-only consumer-package smoke.
- Full `bin/verify` before handoff.

## Progress

- 2026-08-05: Selected from `ROADMAP_NEXT.md` and `ROADMAP.md` after the
  auth-rotation HTTP-status slice. All explicit MCP 2026 feature layers are
  complete, so the next concrete downstream-readiness gap remains auth/session
  correctness. Rejected and malformed initialize cleanup currently validates
  against the captured session generation only, allowing a delayed response
  sent under superseded authorization to clear the active session and cursor.
- 2026-08-05: Serena preflight and overlap checks passed. The only connectanum
  automation process is the current scheduled wrapper, the carried local edits
  are the prior plan's hosted-evidence bookkeeping, and pre-change
  `bin/test-fast` passed at exact head `30a98a0`.
- 2026-08-05: Fail-first coverage reproduced a delayed rejected initialize
  clearing the replacement credential's active session and cursor. Initialize
  failure cleanup now requires both the request's captured session and
  authorization generations to remain current. Successful initialize remains
  session-authoritative so proactive same-principal credential refresh can
  complete in flight, while HTTP 404 cleanup remains session-authoritative.
- 2026-08-05: Three focused regressions cover delayed rejected and malformed
  initialize responses after validated grant/token replacement, successful
  in-flight initialize after replacement, and rejected replacement ownership.
  All 140 Streamable HTTP client tests and focused client analysis pass. The
  neutral generated client-only consumer package proves the stale-initialize
  failure and replacement-bearer contract from both source-path and globally
  activated package boundaries.
- 2026-08-05: Full `bin/verify` passes formatting, analysis, 113 Rust core
  tests, 52 Rust FFI tests, 360 Dart core tests, 94 MCP tests, the complete
  220-case MCP/client suite, all 96 benchmark tests including 36 live WAMP
  workloads, all 384 router tests, 13 native follow-ups, Chrome/Dart2Wasm, and
  every isolated and globally activated consumer/CLI smoke.

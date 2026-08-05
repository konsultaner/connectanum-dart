# Exec Plan: MCP Client Resume-Cursor Concurrency

## Status

Completed.

## Goal

Prevent delayed compatibility-era SSE responses from overwriting a newer MCP
Streamable HTTP resume cursor while the session itself remains unchanged.

## Scope

- Give caller-managed and response-managed `lastEventId` state an opaque
  ownership generation independent of the session generation.
- Snapshot resume ownership before each compatibility GET/SSE and POST/SSE
  request's first await.
- Require both session and resume ownership before a response can replace or
  clear the active cursor.
- Keep successful initialize and session cleanup authoritative over resume
  state.
- Prove the public behavior through focused client regressions and the neutral
  generated client-only consumer package.

## Non-Goals

- Compare or order opaque MCP event identifiers.
- Serialize concurrent Streamable HTTP requests.
- Change session-header, protocol-version, or authorization ownership rules.
- Add automatic notification acknowledgment or persistence.

## Verification

- Pre-change `bin/test-fast`.
- Fail-first regressions for delayed GET/SSE and POST/SSE cursor capture after
  caller replacement on the same session.
- A concurrent-response regression proving a newer completed response retains
  cursor ownership when an older response finishes later.
- Focused client analysis and Streamable HTTP client tests.
- Generated client-only consumer-package smoke.
- Full `bin/verify` before handoff.

## Progress

- 2026-08-05: Selected from `ROADMAP_NEXT.md` and `ROADMAP.md` after completing
  initialize auth-rotation concurrency. Explicit MCP 2026 feature layers and
  WAMP release gates are complete, so the next concrete downstream-readiness
  gap remains compatibility-era auth/session correctness. Session lifecycle
  ownership protects a replacement session, but `lastEventId` has no separate
  ownership generation; a delayed SSE response can therefore overwrite a
  caller-installed or newer response cursor while the session stays unchanged.
- 2026-08-05: Serena preflight and overlap checks passed. The only connectanum
  automation process is the current scheduled wrapper, and the carried local
  edits are the prior plan's hosted-evidence bookkeeping.
- 2026-08-05: Pre-change `bin/test-fast` passed: analyzer, slow tooling and
  audit regressions, 360 core tests, 94 MCP protocol tests, 220 cumulative MCP
  and client tests, 96 benchmark tests including 36 live WAMP cases, generated
  package/global/CLI/router smokes, and the relevant router/native suites. The
  two bounded router-shutdown `Broken pipe` lines remain the known harmless
  teardown noise.
- 2026-08-05: Three fail-first regressions reproduced the ownership gap: a
  delayed GET/SSE overwrote a caller replacement, a delayed POST/SSE overwrote
  a caller replacement, and an older delayed GET/SSE overwrote the cursor from
  a newer completed POST/SSE response.
- 2026-08-05: Added a resume-state token independent of session ownership.
  Compatibility GET/SSE and POST/SSE requests now snapshot that token before
  their first await, and an SSE response may replace or clear `lastEventId`
  only while it still owns both session and resume state. Caller assignments,
  successful response capture, successful initialize, and session cleanup
  each advance the opaque resume generation.
- 2026-08-05: Focused analysis passed, all 143 Streamable HTTP client tests
  passed, and the neutral generated client-only consumer smoke passed with a
  live delayed-GET/newer-POST cursor ordering check.
- 2026-08-05: Full `bin/verify` passed formatting and analysis, 113 Rust core
  tests, 52 Rust FFI tests, 360 Dart core tests, 94 MCP tests, the complete
  223-case MCP/client suite, all 96 benchmark tests including 36 live WAMP
  workloads, all 384 router tests, 13 native follow-ups, Chrome/Dart2Wasm, and
  every isolated and globally activated consumer/CLI smoke. The bounded
  router-shutdown `Broken pipe` output remains teardown-only noise; no test
  failed.
- 2026-08-05: Commit `bcf2555` is on both maintained `master` branches.
  Exact-head GitHub CI `31008088792`, Dart Package Publish Dry Run
  `31008088759`, WAMP Profile Benchmarks `31008088758`, and Router Image dry
  run `31008103652` passed on their first attempts. CI uploaded coverage
  artifact `8931698086`, WAMP uploaded benchmark artifact `8931426941`, and
  Router Image uploaded preview artifact `8931204162` plus Docker build
  records `8931319541` and `8931319025`. The comprehensive strict
  deployment-chain audit passes with clean exact-head CI logs, loaded-image
  MCP runtime smoke, multi-architecture image build, and every required
  branch, workflow, package, native-release, publish-dry-run, benchmark, and
  registry gate clean. Release-candidate readiness remains intentionally
  non-gating until an approved numeric RC tag points at the release commit.

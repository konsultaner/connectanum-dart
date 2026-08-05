# Exec Plan: MCP Client Tool-Catalog State Integrity

## Status

Complete.

## Goal

Keep the public MCP client's tool-parameter header cache transactional and
deterministic when tool catalog pages are malformed or overlap in flight.

## Scope

- Validate a complete tool catalog page, including `nextCursor`, before it can
  update cached `x-mcp-header` parameter routing.
- Give each standard, direct JSON, and Connectanum tool catalog request a
  request-order generation captured before its first await.
- Apply cache mutations per tool only when the response is not older than the
  last successful response that updated that tool.
- Preserve cache accumulation for disjoint and paginated catalog entries.
- Prove the public behavior through focused client regressions and the neutral
  generated client-only consumer package.

## Non-Goals

- Treat an omitted tool in one catalog page as globally removed.
- Serialize concurrent catalog requests.
- Change tool schema validation or public catalog result shapes.
- Change MCP session, authorization, protocol, or resume ownership rules.

## Verification

- Pre-change `bin/test-fast`.
- Fail-first regression proving an invalid cursor cannot poison a previously
  valid tool-parameter header mapping.
- Fail-first regression proving a delayed older catalog response cannot
  overwrite a newer mapping for the same tool.
- Regression preserving concurrent disjoint tool mappings.
- Focused client analysis and Streamable HTTP client tests.
- Generated client-only consumer-package smoke.
- Full `bin/verify` before handoff.

## Progress

- 2026-08-05: Selected from `ROADMAP_NEXT.md` and `ROADMAP.md` after completing
  resume-cursor concurrency. Explicit MCP 2026 feature layers and WAMP release
  gates are complete, so the next concrete downstream-readiness gap is public
  tool-catalog state integrity. The client currently updates cached
  `x-mcp-header` routing before validating `nextCursor`, and overlapping
  catalog responses update the same cache in completion order without request
  ownership.
- 2026-08-05: Serena preflight and overlap checks passed. The only connectanum
  process is the current scheduled wrapper, its lock PID is live, both remotes
  match `bcf2555f`, and the carried local edits are the completed prior plan's
  hosted-evidence bookkeeping.
- 2026-08-05: Pre-change `bin/test-fast` passed: 360 core tests, 94 MCP tests,
  223 cumulative client tests, and 96 benchmark tests including 36 live WAMP
  scenarios, plus generated client/server, router-hosted MCP, package-install,
  and router CLI consumer smokes.
- 2026-08-05: Added fail-first client regressions. The malformed-page case
  observed `mcp-param-poisonedmessage` instead of the previously valid header,
  and the overlap case observed `mcp-param-oldermessage` instead of the newer
  request's mapping. The disjoint overlap control already passed.
- 2026-08-05: Tool catalog helpers now validate the full page before committing
  cache state and apply request-order generations per tool across standard,
  direct JSON, and Connectanum catalog requests. All 146 focused Streamable
  HTTP client tests pass, including the three new state-integrity regressions.
- 2026-08-05: The generated client-only consumer package now proves malformed
  catalog isolation and overlapping standard/Connectanum catalog ordering from
  public package APIs; its dependency resolution, analysis, package executable
  checks, and runtime smoke pass.
- 2026-08-05: Final `git diff --check`, `bash -n bin/common.sh`, and
  `bin/verify` pass. Full verification covered 113 Rust core tests, 52 Rust FFI
  tests, 360 Dart core tests, all 94 MCP tests, the complete 226-case
  MCP/client suite, all 96 benchmark tests including 36 live WAMP workloads,
  all 384 router tests, 13 native follow-ups, Chrome/Dart2Wasm, and every
  isolated and globally activated consumer/CLI smoke. The implementation is
  ready to push; exact-head hosted workflows and the strict deployment-chain
  audit remain.

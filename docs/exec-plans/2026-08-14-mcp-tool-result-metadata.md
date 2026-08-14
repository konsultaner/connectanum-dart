# Exec Plan: MCP Tool Result Metadata

Status: complete; local and hosted deployment-chain evidence clean
Owner: Codex
Created: 2026-08-14
Last updated: 2026-08-14

## Goal

Preserve MCP result `_meta` from tool handlers and WAMP result details through
package APIs, router-hosted Streamable HTTP responses, and downstream client
validation so applications and agents can consume protocol metadata without
private integration assumptions.

## Scope

- In scope:
  - Public metadata on ordinary, error, text, and `input_required` tool results.
  - Lossless WAMP result-detail projection into MCP result metadata while
    retaining the existing structured result envelope.
  - Streamable HTTP client validation for metadata on complete and
    `input_required` results.
  - Router-hosted coverage proving handler metadata survives modernization and
    the reserved server identity remains router-authoritative.
  - Neutral package and integration tests for direct JSON and standard
    `tools/call` consumers.
- Out of scope:
  - Implementing MCP task, sampling, or completion APIs.
  - Changing WAMP result semantics or the router authorization model.
  - Assigning product-specific meaning to arbitrary result metadata.

## Files Expected To Change

- `packages/connectanum_mcp/lib/src/tools/tool.dart`
- `packages/connectanum_mcp/lib/src/tools/wamp_tool_delegate.dart`
- `packages/connectanum_mcp/test/tools_test.dart`
- `packages/connectanum_mcp/test/wamp_tool_delegate_test.dart`
- `packages/connectanum_client/lib/src/mcp/streamable_http_client.dart`
- `packages/connectanum_client/test/mcp/streamable_http_client_test.dart`
- Router tests where the hosted response boundary needs explicit coverage.
- Public package notes and MCP research only where the contract materially
  changes.
- `docs/project_state.md` and this plan.

## Preconditions

- Commit `a50e9bc3` is published to both maintained `master` branches and its
  exact-head CI and Router Image evidence are green.
- The MCP 2026-07-28 schema defines optional result `_meta`, including on
  `input_required` results; no credential or product decision is required.

## Plan

1. Run the pre-change fast gate and add fail-first package, client, WAMP, and
   router contracts for result metadata.
2. Extend the public tool result model, WAMP lossless mapper, and Streamable
   HTTP validation while preserving existing wire shapes and compatibility.
3. Run focused package/client/router checks, formatting, analysis, and full
   repository verification.
4. Commit and push the implementation, then collect exact-head hosted and
   strict deployment-chain evidence required by the changed package paths.

## Verification

- `dart test packages/connectanum_mcp/test/tools_test.dart -r expanded`
- `dart test packages/connectanum_mcp/test/wamp_tool_delegate_test.dart -r expanded`
- Focused Streamable HTTP client and router tests selected by the regressions.
- `dart analyze packages/connectanum_mcp packages/connectanum_client packages/connectanum_router`
- `bin/test-fast`
- `bin/verify`

## Decision Log

- 2026-08-14: All earlier router-hosted auth, direct JSON, pub/sub,
  Streamable HTTP, and official SDK readiness slices are complete. Result
  `_meta` is the next explicit future layer in the checked-in MCP research and
  is a concrete downstream integration boundary in the current 2026 protocol.
- 2026-08-14: Router modernization already merges handler-authored `_meta`
  while overwriting `io.modelcontextprotocol/serverInfo` with canonical router
  identity. This milestone will preserve that authority boundary instead of
  replacing it.
- 2026-08-14: `McpToolResult.meta` is the public Dart spelling for wire-level
  `_meta`. The lossless WAMP mapper mirrors JSON-compatible result details into
  metadata while retaining `structuredContent.details`; MRTR control fields are
  excluded from `input_required` metadata, but additional callee details are
  preserved.
- 2026-08-14: The Streamable HTTP client validates `_meta` independently on
  complete and `input_required` paths. A native stateless router regression
  proves WAMP metadata survives direct JSON tool dispatch and a callee cannot
  replace canonical router server identity.
- 2026-08-14: Commit `d3777842` is published to both maintained `master`
  branches. Exact-head CI `31802081048`, Dart Package Publish Dry Run
  `31802081107`, WAMP Profile Benchmarks `31802081038`, and Router Image dry
  run `31802189834` all pass. No RC tag is selected without release approval.

## Handoff

- The pre-change `bin/test-fast` gate exits zero. Fail-first MCP package tests
  showed the missing public `meta` parameter and dropped WAMP metadata; the
  client accepted a non-object `_meta`; and the native router call returned
  only canonical server identity without callee metadata.
- Post-change focused MCP, client, and native router regressions pass. The full
  affected MCP/client test command passes 393 cases, and Dart analysis is clean
  across `connectanum_mcp`, `connectanum_client`, and `connectanum_router`.
- `bin/verify` exits zero with formatting unchanged, 114 Rust core tests, all
  52 FFI tests, 364 Dart core tests, 112 MCP tests, the 281-case client MCP
  suite, 97 benchmark tests including all 37 live WAMP workloads, the 442-case
  router suite, 6 remote-auth tests, 13 native follow-ups, all consumer smokes,
  Chrome, and Dart2Wasm green.
- Exact-head CI retains coverage artifact `9220142460`; WAMP retains benchmark
  artifact `9219868268`; Router Image retains preview artifact `9219712404`
  and Docker build records `9219857274` and `9219856678`. The Router Image run
  passes its loaded-image MCP runtime smoke and multi-architecture build while
  avoiding GHCR login. The comprehensive strict deployment-chain audit exits
  zero with clean exact-head CI logs and all required package, native-release,
  Router Image, WAMP, workflow, protected-branch, and package-visibility gates
  clean.

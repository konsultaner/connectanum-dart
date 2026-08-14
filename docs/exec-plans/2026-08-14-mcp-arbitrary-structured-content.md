# Exec Plan: MCP Arbitrary Structured Content

Status: implementation complete; local verification clean; commit and hosted evidence pending
Owner: Codex
Created: 2026-08-14
Last updated: 2026-08-14

## Goal

Allow MCP tools and Streamable HTTP consumers to exchange every JSON value in
`structuredContent`, including arrays, scalars, and explicit `null`, while
preserving the distinction between an omitted field and a present null value.

## Scope

- In scope:
  - A public tool-result API that accepts arbitrary JSON-compatible structured
    content and exposes whether the field was supplied.
  - Wire serialization that preserves objects, arrays, scalars, and explicit
    null values.
  - Streamable HTTP client validation shared by standard and direct JSON tool
    calls without imposing an object-only shape.
  - Neutral package-boundary smoke and focused regressions for the supported
    value shapes.
  - Public package notes and checked-in MCP research describing the stable
    protocol contract.
- Out of scope:
  - MCP Tasks, sampling, completions, or other opt-in extensions.
  - Changing the object envelope produced by Connectanum's WAMP-specific tool
    helpers.
  - Validating tool-specific output schemas inside the transport client.

## Files Expected To Change

- `packages/connectanum_mcp/lib/src/tools/tool.dart`
- `packages/connectanum_mcp/test/tools_test.dart`
- `packages/connectanum_client/lib/src/mcp/streamable_http_client.dart`
- `packages/connectanum_client/test/mcp/streamable_http_client_test.dart`
- `bin/common.sh`
- Public package notes, MCP research, and roadmap/state files where the
  contract materially changes.

## Preconditions

- Commit `d3777842` is published to both maintained `master` branches and its
  exact-head deployment-chain evidence is green.
- The pre-change `bin/test-fast` gate exits zero.
- The MCP 2026-07-28 schema types `CallToolResult.structuredContent` as an
  unrestricted JSON value; no product decision or credential is required.

## Plan

1. Add fail-first MCP package and Streamable HTTP client coverage for objects,
   arrays, scalars, explicit null, and omission.
2. Broaden the public result model while adding explicit presence semantics,
   then remove the client-side object-only restriction.
3. Extend the neutral MCP server package smoke and update public compatibility
   notes and protocol research.
4. Run focused package/client checks, formatting, analysis, and full repository
   verification.
5. Commit and push the implementation, then collect exact-head hosted and
   strict deployment-chain evidence required by the changed package paths.

## Verification

- `dart test packages/connectanum_mcp/test/tools_test.dart -r expanded`
- Focused Streamable HTTP client regressions.
- `bash -lc 'source bin/common.sh && run_mcp_server_package_smoke'`
- `dart analyze packages/connectanum_mcp packages/connectanum_client`
- `bin/verify`

## Decision Log

- 2026-08-14: The original router-hosted MCP auth, endpoint, direct JSON,
  pub/sub, Streamable HTTP, resources/prompts, and metadata readiness slices
  are complete. Arbitrary structured tool results are the next stable core
  compatibility gap affecting ordinary downstream tool calls.
- 2026-08-14: MCP Tasks remain demand-driven because they are an opt-in
  extension. This slice follows the stable 2026-07-28 `CallToolResult` schema
  first.
- 2026-08-14: Tool-specific output-schema enforcement belongs to the tool or
  application layer. The generic transport must accept any valid JSON value.
- 2026-08-14: `McpToolResult` uses a private absence sentinel and public
  `hasStructuredContent` getter so omitted and explicitly null fields remain
  distinguishable without adding a second constructor family. The shared
  client result validator continues to enforce content blocks, `isError`, and
  `_meta`, but leaves the already-decoded JSON structured value unrestricted.
- 2026-08-14: Focused client coverage exercises modern standard JSON,
  request-scoped SSE, and lifecycle-free direct JSON. The installed-package
  smoke exercises list and explicit-null results through `McpServer` using
  only the public package entrypoint.

## Handoff

- Pre-change `bin/test-fast` exits zero. Fail-first tests show the public server
  API rejected non-object values and the client rejected a valid result array.
- Post-change focused MCP and client suites, the neutral installed-package
  server smoke, shell validation, diff checks, and package analysis pass.
- `bin/verify` exits zero with formatting unchanged, 114 Rust core tests, all
  52 FFI tests, 364 Dart core tests, 113 MCP tests, the 282-case client MCP
  suite, 97 benchmark tests including all 37 live WAMP workloads, the 442-case
  router suite, 6 remote-auth tests, 13 native follow-ups, all consumer smokes,
  Chrome, and Dart2Wasm green. Commit/push and exact-head hosted evidence
  remain.

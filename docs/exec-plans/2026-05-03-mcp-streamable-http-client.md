# Exec Plan: MCP Streamable HTTP Client

Status: completed
Owner: Codex
Created: 2026-05-03
Last updated: 2026-05-03

## Goal

Make router-hosted MCP directly usable from Dart IO consumer applications by
shipping a small Streamable HTTP client that handles MCP session headers, JSON
request/response negotiation, POST-initiated SSE responses, GET/SSE polling,
resume cursors, and session deletion.

## Scope

- Keep the existing universal `connectanum_mcp.dart` export free of `dart:io`.
- Add an IO-only `connectanum_mcp_io.dart` entrypoint for Streamable HTTP.
- Support custom request headers so authenticated router MCP routes can be used
  with bearer tokens or other deployment-specific HTTP auth.
- Parse SSE event IDs, event names, retry hints, empty primer events, and JSON
  event data.
- Add tests against a local fake MCP HTTP endpoint for initialize,
  initialized notification, POST/SSE request responses, GET/SSE polling,
  JSON-only POST compatibility, session deletion, custom auth headers, and
  typed HTTP failures.

## Verification

- `bin/test-fast`
- `dart analyze packages/connectanum_mcp`
- `dart test packages/connectanum_mcp -r expanded`
- `git diff --check`
- `bin/verify`
- Hosted GitHub Actions and deployment-chain audit after push

## Progress

- 2026-05-03: Started after branch-head hosted deployment evidence for
  `a84dcea` was clean and a fresh pre-change `bin/test-fast` passed locally.
- 2026-05-03: Added `connectanum_mcp_io.dart`,
  `McpStreamableHttpClient`, SSE parsing, typed HTTP exceptions, package-level
  fake-endpoint coverage, and a real router-hosted MCP smoke assertion that
  initializes a Streamable HTTP session, receives POST/SSE tool responses, and
  calls a router-backed tool through the new client.
- 2026-05-03: Focused checks passed:
  `dart analyze packages/connectanum_mcp packages/connectanum_router`,
  `dart test packages/connectanum_mcp -r expanded`,
  `dart test packages/connectanum_router/test/router_integration_native_test.dart -r expanded --name "MCP"`,
  and `git diff --check`.
- 2026-05-03: Full local `bin/verify` passed after the Streamable HTTP client
  implementation, router smoke coverage, and roadmap/project-state updates.
- 2026-05-03: Pushed commit `9906d69`
  (`mcp: add streamable http client`) to GitLab and GitHub. Hosted GitHub
  evidence is clean: `CI` run `25282247750` completed successfully with
  `Fast Checks` in 5m40s and `Full Verify` in 8m30s, hosted CI log scan found
  no warning, deprecation, skipped-test, reset, connection-noise, panic, or
  failure patterns, `WAMP Profile Benchmarks` run `25282247769` completed
  successfully in 8m01s, `Dart Package Publish Dry Run` run `25282247767`
  completed successfully and covers the checked-out head, and Native Artifacts
  dry-run `25192553399` remains clean and relevant because no
  native-release-sensitive paths changed.

## Decision Log

- 2026-05-03: Use a separate `connectanum_mcp_io.dart` entrypoint so adding
  `dart:io` transport support does not make the main MCP primitives library
  unusable for non-IO targets.
- 2026-05-03: Send explicit `Content-Length` JSON request bodies instead of
  chunked transfer encoding because the native router-hosted HTTP ingress
  rejects chunked MCP request bodies.

## Handoff

Complete. Remaining MCP work should be driven by concrete consumer integration
gaps after this router-hosted endpoint and Dart IO Streamable HTTP client path.

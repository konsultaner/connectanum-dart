# Exec Plan: Router MCP SSE Resumability

Status: completed
Owner: Codex
Created: 2026-05-03
Last updated: 2026-05-03

## Goal

Make router-hosted MCP GET/SSE useful for real Streamable HTTP clients by
adding bounded server-to-client notification delivery and `Last-Event-ID`
resume behavior on the existing route-authenticated MCP endpoint.

## Scope

- Keep MCP hosted by router `type: mcp` HTTP routes.
- Keep SSE state scoped to the same route/principal/MCP HTTP session key as
  POST and DELETE.
- Advertise tool-list change capability on router-hosted MCP endpoints and
  enqueue `notifications/tools/list_changed` when the route-visible catalog
  changes after MCP initialization.
- Support `Last-Event-ID` as a per-stream replay cursor and reject unknown
  cursors instead of replaying unrelated stream messages.
- Use a bounded in-memory event history so polling clients can resume without
  unbounded process memory growth.
- Add native router integration coverage for notification delivery, no duplicate
  replay after a cursor, and unknown-cursor rejection.

## Verification

- `bin/test-fast`
- `dart analyze packages/connectanum_router packages/connectanum_mcp`
- `dart test packages/connectanum_router/test/router_integration_native_test.dart -r expanded --name "MCP"`
- `dart test packages/connectanum_mcp -r expanded`
- `git diff --check`
- `bin/verify`
- Hosted GitHub Actions and deployment-chain audit after push

## Progress

- 2026-05-03: Started after a clean branch-head deployment-chain audit at
  `c153075` and a passing pre-change `bin/test-fast`.
- 2026-05-03: Implemented a bounded per-endpoint SSE event history on the
  router-hosted MCP route. GET/SSE now reserves pending server notifications for
  the response attempt, commits them after a successful stream write, and
  restores them if the stream cannot be opened or written.
- 2026-05-03: Router-hosted MCP endpoints now advertise `tools.listChanged` and
  enqueue `notifications/tools/list_changed` when the route-visible tool catalog
  changes after MCP initialization.
- 2026-05-03: Added focused integration coverage for server-to-client tool-list
  notifications, `Last-Event-ID` resume polling without duplicate delivery, and
  unknown cursor rejection. Focused `dart analyze
  packages/connectanum_router packages/connectanum_mcp`, `dart test
  packages/connectanum_router/test/router_integration_native_test.dart -r
  expanded --name "MCP"`, and `dart test packages/connectanum_mcp -r expanded`
  passed.
- 2026-05-03: Full local `bin/verify` passed after the SSE resumability
  implementation and docs updates. It included formatting, Rust native/FFI
  tests, Python package-artifact checks, MCP package tests, client/native
  tests, auth-server tests, bench integration tests, the full router package
  suite including the updated MCP Streamable HTTP regression, zero-copy router
  checks, and Chrome Dart2Wasm WebSocket transport tests.
- 2026-05-03: Pushed commit `eb3d9e6`
  (`mcp: add resumable router sse events`) to GitLab and GitHub. Hosted GitHub
  evidence is clean: `CI` run `25280137967`, `WAMP Profile Benchmarks` run
  `25280137976`, and `Dart Package Publish Dry Run` run `25280137972` all
  completed successfully. The strict add-router deployment-chain audit passed
  with a clean CI job set, clean CI log scan, clean relevant Dart package
  dry-run, and the existing Native Artifacts dry-run `25192553399` still
  relevant because no native-release-sensitive paths changed.

## Decision Log

- 2026-05-03: The current MCP Streamable HTTP transport spec
  (https://modelcontextprotocol.io/specification/2025-11-25/basic/transports)
  says SSE event IDs should be globally unique within the session/client and
  encode enough stream identity for `Last-Event-ID` replay; resumability must
  not replay messages that belong to a different stream. The router therefore
  uses per-session endpoint history and per-stream event IDs instead of one
  global broadcast queue.
- 2026-05-03: This slice keeps GET/SSE unrelated to request/response POST
  bodies. The spec allows GET streams to carry server requests/notifications but
  not unrelated JSON-RPC responses, so request responses continue to use the
  existing JSON POST path.

## Handoff

Complete. Remaining future MCP Streamable HTTP work is POST-initiated SSE
response streams if a client integration needs request-scoped streamed results
or server requests during long-running tool calls.

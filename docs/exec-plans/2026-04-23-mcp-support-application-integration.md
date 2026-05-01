# Exec Plan: MCP Support for Application Integration

## Goal

Make MCP support the next product-readiness milestone so downstream applications
can use Connectanum as an agent/tool integration layer without carrying a private
protocol bridge.

## Priority

- Keep the CI chain green first.
- Fix blockers in already-shipped functionality before adding MCP code.
- Once CI and shipped paths are clean, work on MCP before speculative H3, kTLS,
  E2EE, or benchmark exploration.

## Scope

- Research the current official MCP lifecycle, transport, capability, tool,
  prompt, and resource contracts, then capture implementation-impacting
  decisions in checked-in docs.
- Define the first supported Connectanum mapping for MCP server sessions,
  request/response handling, tool discovery, tool calls, and optional resource
  or prompt exposure.
- Provide a Dart package-level API that is practical to embed from downstream
  applications.
- Use `packages/connectanum_core` as the local design reference for API shape:
  typed protocol models, serializer-independent payload boundaries, explicit
  errors, a small barrel export, and focused tests. MCP should not inherit WAMP
  semantics, but it should inherit that project's disciplined package style.
- Keep the initial implementation narrow enough to verify with smoke tests:
  initialization, capability negotiation, tool listing, tool invocation, and
  clean shutdown/error behavior.
- Decide whether the first transport should be stdio, HTTP/streaming HTTP, or a
  Connectanum-router-backed adapter after the spec and application usage shape
  are documented.
- Preserve the existing auth/deployment story: no hidden secrets, explicit local
  development mode, and clear guidance for networked/server deployments.

## Non-Goals

- Full MCP ecosystem parity in the first slice.
- Replacing WAMP as Connectanum's internal protocol.
- Adding deployment secrets or downstream-application-specific private
  configuration to this repo.
- Speculative benchmark expansion unless it protects the MCP path or a release
  decision.

## References to Check Before Implementation

- Checked-in research/design note:
  `docs/mcp_integration_research.md`
- Official MCP lifecycle docs:
  https://modelcontextprotocol.io/specification/latest/basic/lifecycle
- Official MCP transport docs:
  https://modelcontextprotocol.io/specification/latest/basic/transports
- Official MCP tools docs:
  https://modelcontextprotocol.io/specification/latest/server/tools
- Official MCP 2026 roadmap:
  https://blog.modelcontextprotocol.io/posts/2026-mcp-roadmap/

## Verification Plan

- Run `bin/test-fast` before code changes.
- Add focused unit/integration tests for the MCP bridge/server package surface.
- Run targeted package tests after each MCP implementation slice.
- Run `bin/verify` before handoff.
- Watch hosted CI after pushes and restore green before starting unrelated work.

## Status

- 2026-04-23: Plan opened and promoted above exploratory transport/benchmark
  work because downstream application integration needs MCP support.
- 2026-04-23: Initial MCP research/design captured in
  `docs/mcp_integration_research.md`. Recommended first shape is a new
  `packages/connectanum_mcp` package with a transport-independent Dart server
  core, a stdio adapter, and Streamable HTTP/router integration after the core
  tool path is green.
- 2026-04-23: User confirmed `connectanum_core` may be used for design ideas.
  The MCP package should reuse its typed, transport-neutral package style while
  keeping MCP semantics separate from WAMP.
- 2026-04-23: Created `packages/connectanum_mcp` as the first MCP package
  slice. It now has typed protocol constants/errors, server info/capability
  objects, a transport-independent `McpServer`, callback-backed tool registry,
  in-memory lifecycle tests, and `tools/list` / `tools/call` tests. The root
  `bin/test-fast` and `bin/test-all` scripts now include the MCP package tests.
- 2026-04-23: Added the stdio transport adapter plus
  `packages/connectanum_mcp/example/stdio_echo_server.dart`. Focused stdio
  tests now cover newline-delimited JSON-RPC request handling, notifications
  without response lines, parse errors, continued processing after malformed
  input, and EOF shutdown behavior.
- 2026-04-23: `dart analyze packages/connectanum_mcp`,
  `dart test packages/connectanum_mcp -r expanded`, and `bin/verify` passed on
  Darwin arm64 after the stdio adapter slice.
- 2026-04-23: Added `McpWampToolDelegate` for forwarding MCP tool calls to
  Connectanum WAMP procedures through an existing `connectanum_client`
  `Session`. The default mapping sends MCP arguments as WAMP kwargs and returns
  a lossless JSON-shaped MCP tool result; custom argument builders and result
  mappers are supported. Focused tests cover the default mapping, custom
  mapping, and a real `Session.callSinglePayload` adapter path against a fake
  transport.
- 2026-04-23: `dart analyze packages/connectanum_mcp`,
  `dart test packages/connectanum_mcp -r expanded`, and `bin/verify` passed on
  Darwin arm64 after the WAMP delegate slice.
- 2026-05-01: Rechecked the official MCP 2025-11-25 tools/pagination
  requirements and added cursor-safe `tools/list` pagination for larger application
  tool catalogs. `McpServer(toolListPageSize: ...)` now emits stable opaque
  `nextCursor` values and rejects malformed or stale cursors with
  `invalidParams` instead of silently replaying the full tool list.
- 2026-05-01: Pre-change `bin/test-fast` passed before the MCP pagination
  slice. Focused `dart analyze packages/connectanum_mcp` and
  `dart test packages/connectanum_mcp -r expanded` passed after the slice.
- 2026-05-01: Full local `bin/verify` passed after the MCP pagination slice,
  including formatting, Rust native/FFI tests, MCP tests, client/native tests,
  auth-server tests, bench integration tests, router tests, zero-copy publish
  tests, and Chrome Dart2Wasm WebSocket transport tests.
- 2026-05-01: Hosted GitHub evidence for `77e34de`
  (`mcp: paginate tool listings`) is clean: `CI` run `25198143182` passed
  (`Fast Checks` 5m25s, `Full Verify` 8m23s), `Dart Package Publish Dry Run`
  run `25198143194` passed in 19s, and the strict deployment-chain audit/log
  scan found no warning, deprecation, skipped-test, reset, connection-noise,
  panic, or failure patterns.
- 2026-05-01: Public MCP package readability follow-up improved
  `packages/connectanum_mcp/README.md` for downstream application embedders.
  The README now distinguishes the package-local stdio/WAMP-backed tool path
  from router-hosted HTTP MCP routes, shows a copy-paste JSON-RPC
  initialize/list/call sequence, documents `toolListPageSize` cursor behavior,
  and explains the default WAMP tool delegation mapping for applications.
  Pre-change `bin/test-fast` passed before the edit; focused
  `dart analyze packages/connectanum_mcp`,
  `dart test packages/connectanum_mcp -r expanded`, and `git diff --check`
  passed after it. Full local `bin/verify` also passed after the README slice,
  including formatting, Rust native/FFI tests, MCP tests, client/native tests,
  bench integration tests, router tests, zero-copy publish tests, and Chrome
  Dart2Wasm WebSocket transport tests. Hosted GitHub evidence for `6c403ee`
  is clean: `CI` run `25202524041` passed (`Fast Checks` 5m22s,
  `Full Verify` 8m02s), `Dart Package Publish Dry Run` run `25202524047`
  passed in 22s and covers the package README change, and the strict
  deployment-chain audit/log scan found no warning, deprecation, skipped-test,
  reset, connection-noise, panic, or failure patterns.
- 2026-05-01: Added a declared WAMP API helper for application embedders.
  `McpWampApi` can turn declared procedures into WAMP-backed MCP tools, expose
  API list/describe metadata tools, and optionally expose bounded
  publish/subscribe/poll/unsubscribe tools for declared WAMP topics.
  `McpWampApiMetadata.publishesEvents` now derives MCP-visible topics
  automatically, so an API/procedure registration can advertise the event
  surface agents may publish, subscribe to, and poll. Focused tests pin
  procedure metadata exposure, metadata-derived topics, publish option
  forwarding, buffered topic polling, queue drops, unsubscribe behavior, and
  the early-event subscription buffer path.
- 2026-05-01: Added the first router-hosted HTTP MCP endpoint. Router
  `HttpRouteActionType.mcp` now handles MCP JSON-RPC over HTTP POST. The route
  is translated into the native HTTP route table and intercepted by Dart, so the
  router itself acts as the MCP endpoint instead of requiring a separate MCP
  server process. When no bearer-auth session is required, tools are backed by
  the router internal WAMP session; otherwise the existing protected HTTP
  session path is reused. The endpoint exposes configured and currently
  registered exact procedures/topics, metadata-derived event topics, and
  standard WAMP meta tools from router snapshots. Focused verification:
  `dart analyze packages/connectanum_router`,
  `dart test packages/connectanum_router/test/router_json_test.dart -r expanded`,
  `cd packages/connectanum_router && dart test test/router_integration_native_test.dart -r expanded --exclude-tags zero_copy_publish`,
  and `cd packages/connectanum_router && CONNECTANUM_FORWARD_NATIVE_PUBLISH=1 dart test test/router_integration_native_test.dart -r expanded --tags zero_copy_publish --chain-stack-traces`.
- 2026-05-01: Full local `bin/verify` passed after the declared WAMP API helper
  and router-hosted HTTP MCP slice, including formatting, Rust native/FFI tests,
  MCP tests, client/native tests, auth-server tests, bench integration tests,
  full router package tests, zero-copy publish tests, and Chrome Dart2Wasm
  WebSocket transport tests.
- First usable MCP bridge path is complete for local stdio and router-hosted
  JSON-RPC `POST` request/response clients. Remaining MCP follow-up should be
  driven by a concrete application need, such as resources/prompts, full
  Streamable HTTP GET/SSE/session semantics, or more auth/deployment examples.

# Exec Plan: MCP Support for groli/app

## Goal

Make MCP support the next product-readiness milestone so `groli/app` can use
Connectanum as an agent/tool integration layer without carrying a private
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
- Provide a Dart package-level API that is practical to embed from
  `groli/app`.
- Use `packages/connectanum_core` as the local design reference for API shape:
  typed protocol models, serializer-independent payload boundaries, explicit
  errors, a small barrel export, and focused tests. MCP should not inherit WAMP
  semantics, but it should inherit that project's disciplined package style.
- Keep the initial implementation narrow enough to verify with smoke tests:
  initialization, capability negotiation, tool listing, tool invocation, and
  clean shutdown/error behavior.
- Decide whether the first transport should be stdio, HTTP/streaming HTTP, or a
  Connectanum-router-backed adapter after the spec and `groli/app` usage shape
  are documented.
- Preserve the existing auth/deployment story: no hidden secrets, explicit local
  development mode, and clear guidance for networked/server deployments.

## Non-Goals

- Full MCP ecosystem parity in the first slice.
- Replacing WAMP as Connectanum's internal protocol.
- Adding deployment secrets or `groli/app`-specific private configuration to
  this repo.
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
  work because `groli/app` needs MCP support.
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
- First usable stdio MCP bridge path is complete. Streamable HTTP/router
  integration remains conditional on whether `groli/app` needs a network MCP
  endpoint, so autonomous continuation should move to the WAMP-profile
  transport performance readiness plan unless that product decision changes.

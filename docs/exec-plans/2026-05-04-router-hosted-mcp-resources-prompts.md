# Exec Plan: Router-Hosted MCP Resources And Prompts

Status: complete; hosted evidence clean
Owner: Codex
Created: 2026-05-04
Last updated: 2026-05-04

## Goal

Make router-hosted MCP endpoints expose the standard MCP resources and prompts
surface directly from route configuration, so consumer applications can provide
read-only context and prompt templates without starting a second MCP server.

## Scope

In scope:

- Add `HttpRouteActionType.mcp` option parsing for configured resources,
  resource templates, prompts, and their list page sizes.
- Advertise `resources` and `prompts` capabilities during MCP `initialize`
  when the route config includes those surfaces.
- Extend the native router MCP integration smoke to prove
  `resources/list`, `resources/read`, `resources/templates/list`,
  `prompts/list`, and `prompts/get` through the router-hosted endpoint.
- Update public MCP docs and implementation research notes so they no longer
  describe router-hosted resources/prompts as unavailable.

Out of scope:

- Automatic projection of application data or prompt registries into MCP.
- MCP resource subscriptions, prompt completions, sampling, or tasks.
- Deployment-chain operator tasks such as branch protection and package
  ownership.

## Files Expected To Change

- `packages/connectanum_router/lib/src/router/router_instance/router_mcp.dart`
- `packages/connectanum_router/test/router_integration_native_test.dart`
- `packages/connectanum_mcp/README.md`
- `docs/examples.md`
- `docs/mcp_integration_research.md`
- `ROADMAP.md`
- `docs/project_state.md`
- `docs/exec-plans/2026-05-04-router-hosted-mcp-resources-prompts.md`

## Plan

1. Parse configured resources, resource templates, and prompts from MCP route
   options and pass them into the router-owned `McpServer`.
2. Advertise matching MCP capabilities and apply route-configured page sizes.
3. Extend the existing router-hosted MCP HTTP smoke with resource/template and
   prompt lifecycle checks.
4. Run focused analysis and the targeted native MCP route test.
5. Run full local verification before handoff.
6. Push the implementation and inspect hosted GitHub deployment-chain evidence.

## Verification

- Pre-change `bin/test-fast` passed on 2026-05-04.
- Focused checks passed on 2026-05-04:
  `dart analyze packages/connectanum_router` and
  `dart test packages/connectanum_router/test/router_integration_native_test.dart -r expanded --plain-name "hosts MCP over HTTP using the router internal session"`.
- Full local `bin/verify` passed on 2026-05-04 after the router-hosted MCP
  resource/prompt implementation. It included formatting, Rust native/FFI
  tests, Python package-artifact checks, MCP package tests, client tests
  including MCP Streamable HTTP/direct JSON helper coverage, auth-server tests,
  bench integration tests, the full router package tests including
  router-hosted MCP and `remote_auth_integration_test`, zero-copy router
  checks, and Chrome Dart2Wasm WebSocket transport tests.
- Hosted GitHub evidence for `09dffab` is clean: `CI` run `25306872679`
  completed successfully with `Fast Checks` and `Full Verify`, `Dart Package
  Publish Dry Run` run `25306872647` completed successfully, and `WAMP Profile
  Benchmarks` run `25306872632` completed successfully. The hosted log scan
  found no actionable Rust/Dart warnings, deprecations, skipped-test lines,
  panics, resets, connection failures, or broken pipes; matches were limited to
  Git checkout's default-branch hint and normal `0 ignored` / filtered-test
  summaries.

## Decision Log

- 2026-05-04: Keep router-hosted resources and prompts explicit in route
  options. Automatic projection from application data or annotations is a
  separate product decision because resources and prompt templates can expose
  sensitive context.

## Handoff

Complete. Commit `09dffab` was pushed to both remotes, local verification is
clean, and hosted GitHub deployment-chain evidence is clean.

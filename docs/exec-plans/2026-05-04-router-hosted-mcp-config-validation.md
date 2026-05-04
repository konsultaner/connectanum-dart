# Exec Plan: Router-Hosted MCP Config Validation

Status: implementation complete; local verification clean
Owner: Codex
Created: 2026-05-04
Last updated: 2026-05-04

## Goal

Fail malformed router-hosted MCP route options during router configuration
build/start instead of deferring parser errors until the first MCP request.

## Scope

In scope:

- Reuse the router-hosted MCP procedure/topic/resource/template/prompt parsers
  as a startup validation path.
- Wire validation into MCP HTTP route native-config generation.
- Add focused router config regressions for invalid MCP resource, WAMP API, and
  prompt options.
- Document that configured router MCP surfaces are validated when the router
  config is built or started.

Out of scope:

- Introducing typed MCP route option model classes.
- Changing the accepted `HttpRouteAction.options` map shape.
- Automatic application data or prompt projection.

## Files Expected To Change

- `packages/connectanum_router/lib/src/router/router_instance/router_controller.dart`
- `packages/connectanum_router/lib/src/router/router_instance/router_mcp.dart`
- `packages/connectanum_router/test/router_json_test.dart`
- `packages/connectanum_mcp/README.md`
- `docs/project_state.md`
- `docs/exec-plans/2026-05-04-router-hosted-mcp-config-validation.md`

## Plan

1. Add an internal MCP route option validation helper that exercises the same
   parsers used by the router-hosted endpoint.
2. Call that helper while building native config for `HttpRouteActionType.mcp`
   routes.
3. Cover malformed resource, WAMP API, and prompt route options in
   `router_json_test.dart`.
4. Run focused router analysis and tests.
5. Run full local verification before handoff.
6. Push the implementation and inspect hosted GitHub deployment-chain evidence.

## Verification

- Pre-change `bin/test-fast` passed on 2026-05-04.
- Focused checks passed on 2026-05-04:
  `dart analyze packages/connectanum_router` and
  `dart test packages/connectanum_router/test/router_json_test.dart -r expanded`.
- Full local `bin/verify` passed on 2026-05-04. It included formatting, Rust
  native/FFI tests, Python package-artifact checks, MCP package tests, client
  tests including MCP Streamable HTTP/direct JSON helper coverage, auth-server
  tests, bench integration tests, the full router package tests including the
  new MCP route-option validation cases and existing router-hosted MCP smoke
  coverage, zero-copy router checks, and Chrome Dart2Wasm WebSocket transport
  tests.

## Decision Log

- 2026-05-04: Keep validation in the existing router build/start path instead
  of adding public typed option classes. That keeps the current map-based
  configuration API stable while still failing bad MCP route config before
  accepting traffic.

## Handoff

Implementation and local verification are complete. Hosted GitHub evidence is
pending after push.

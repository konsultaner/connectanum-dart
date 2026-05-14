# Exec Plan: HTTP Session Proxy Route Action

Status: complete
Owner: Codex
Created: 2026-05-14
Last updated: 2026-05-14

## Goal

Make the configured HTTP `session_proxy` action a release-ready route action
instead of a parsed-but-unwired placeholder, so incoming REST requests can use
the existing internal router session path without requiring a custom external
proxy process.

## Scope

- In scope: Dart config loading/codec coverage, native config generation, and
  synthetic router runtime dispatch for HTTP session-proxy routes.
- Out of scope: file serving, reverse proxy adapters, FastCGI/PHP-FPM adapters,
  and HTTP publish-topic route actions.

## Files Expected To Change

- `packages/connectanum_router/lib/src/router/router_instance/router_controller.dart`
- `packages/connectanum_router/lib/src/router/router_instance/router_binding.dart`
- `packages/connectanum_router/test/router_config_loader_test.dart`
- `packages/connectanum_router/test/router_json_test.dart`
- `packages/connectanum_router/test/router_runtime_test.dart`
- `ROADMAP.md`
- `docs/project_state.md`

## Preconditions

- `bin/test-fast` must pass before edits.
- No product decision is needed because `session_proxy` already exists in the
  public route action enum and maps to the existing internal-session HTTP call
  path.

## Plan

1. Wire `HttpRouteActionType.sessionProxy` through native HTTP route config as
   a translation target using the configured procedure and normal realm
   fallback rules.
2. Route Dart synthetic/non-native HTTP requests with `sessionProxy` through the
   same internal-session dispatch target as `internalCall`.
3. Add focused config-loader, native-config JSON, and runtime dispatch
   regressions.
4. Run focused tests, `bin/verify`, and update project state.

## Verification

- `bin/test-fast`
- `dart test packages/connectanum_router/test/router_config_loader_test.dart -n "session proxy"`
- `dart test packages/connectanum_router/test/router_json_test.dart -n "session proxy|method-specific HTTP route actions"`
- `dart test packages/connectanum_router/test/router_runtime_test.dart -n "session proxy"`
- `bin/verify`

## Decision Log

- 2026-05-14: Chose `session_proxy` before broader adapter work because it is a
  documented config surface already present in the route action enum, and it
  directly advances the HTTP bridge internal-session proxy readiness item.

## Handoff

`session_proxy` routes now parse, encode to native route translation entries,
and dispatch synthetic HTTP requests through router internal sessions. Remaining
HTTP bridge work stays on policy-driven publish/file/custom-handler routes,
middleware hooks, and adapter pipelines. A first `bin/verify` attempt hit a
transient HTTP/3 response-streaming handshake timeout; the focused native test
passed immediately, and the full `bin/verify` rerun passed.

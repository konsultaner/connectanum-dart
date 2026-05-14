# Exec Plan: HTTP Route Rate-Limit Middleware

Status: complete
Owner: Codex
Created: 2026-05-14
Last updated: 2026-05-14

## Goal

Make HTTP bridge routes safer for production use by adding a typed per-route
rate-limit middleware setting that runs in the Dart router binding before
dispatching into WAMP-backed handlers.

## Scope

- In scope: typed route setting, config loader aliases, settings codec
  round-trip, runtime enforcement, and focused tests.
- Out of scope: distributed rate-limit storage, adaptive quotas, external rate
  services, static file adapters, reverse proxy adapters, and custom handler
  pipelines.

## Files Expected To Change

- `packages/connectanum_router/lib/src/router/config/router_settings.dart`
- `packages/connectanum_router/lib/src/router/config/router_config_loader.dart`
- `packages/connectanum_router/lib/src/router/config/router_settings_codec.dart`
- `packages/connectanum_router/lib/src/router/router_instance/router_binding.dart`
- `packages/connectanum_router/test/router_config_loader_test.dart`
- `packages/connectanum_router/test/router_runtime_test.dart`
- `ROADMAP.md`
- `docs/project_state.md`

## Preconditions

- `bin/test-fast` passed on 2026-05-14 before edits.
- Hosted PR CI and package dry-run are clean on the previous pushed head
  `5d8ff5b`.

## Plan

1. Add typed `HttpRouteRateLimitSettings` to the HTTP route action surface.
2. Parse `rate_limit` / `rateLimit` config with clear validation and encode it
   through `RouterSettingsCodec`.
3. Enforce limits in the Dart HTTP route binding before `auth`, `mcp`,
   `publish`, or WAMP RPC dispatch.
4. Return structured `429 Too Many Requests` responses with `Retry-After` and
   rate-limit headers.
5. Add focused config-loader/codec and runtime dispatch regressions.
6. Run focused tests and `bin/verify`.

## Verification

- `bin/test-fast`
- `dart test packages/connectanum_router/test/router_config_loader_test.dart -n "rate-limit"`
- `dart test packages/connectanum_router/test/router_runtime_test.dart -n "rate-limits HTTP routes"`
- `git diff --check`
- `bin/verify`

## Decision Log

- 2026-05-14: Chose rate limiting as the first middleware hook because it is
  a concrete production guard for all HTTP bridge actions, is locally
  testable, and does not require external adapter/product decisions.

## Handoff

HTTP routes now accept typed per-route rate-limit settings, parse common config
aliases, round-trip through the settings codec, enforce limits before WAMP/MCP
dispatch, emit `http_route_rate_limited`, and return structured `429` responses
with retry/rate-limit headers. Hosted CI evidence is still pending for the
commit that contains this slice.

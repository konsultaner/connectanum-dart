# Exec Plan: HTTP Route Concurrency Throttle

Status: complete
Owner: Codex
Created: 2026-05-14
Last updated: 2026-05-14

## Goal

Make HTTP bridge routes safer under load by adding a typed per-route concurrency
throttle that rejects excess in-flight requests before they enter WAMP-backed
handlers.

## Scope

- In scope: typed route setting, config loader aliases, settings codec
  round-trip, runtime enforcement, slot release on completion, and focused
  tests.
- Out of scope: distributed counters, request queueing, adaptive throttles,
  external rate services, static file adapters, reverse proxy adapters, and
  custom handler pipelines.

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
  `4c8e3c5`.

## Plan

1. Add typed `HttpRouteConcurrencyLimitSettings` to the HTTP route action
   surface.
2. Parse `concurrency_limit` / `concurrencyLimit` / `throttle` config with
   clear validation and encode it through `RouterSettingsCodec`.
3. Enforce limits in the Dart HTTP route binding after transport/rate checks
   and before `auth`, `mcp`, `publish`, or WAMP RPC dispatch.
4. Release acquired slots when immediate handlers or pending HTTP calls
   complete.
5. Add focused config-loader/codec and runtime regressions.
6. Run focused tests and `bin/verify`.

## Verification

- `bin/test-fast` passed on 2026-05-14 before edits.
- `dart test packages/connectanum_router/test/router_config_loader_test.dart -n "middleware limits"` passed.
- `dart test packages/connectanum_router/test/router_runtime_test.dart -n "throttles concurrent HTTP routes"` passed.
- `git diff --check` passed.
- `bin/verify` passed on 2026-05-14.
- GitHub PR CI #25860173425 passed on `18a1563` with `Fast Checks` and
  `Full Verify` green.
- GitHub Dart Package Publish Dry Run #25860173360 passed on `18a1563`.
- `bin/audit-github-deployment-chain --branch codex/post-rc-production-readiness --run-limit 1 --require-clean-latest-ci --require-clean-latest-ci-logs --require-clean-dart-package-publish-dry-run`
  passed with clean latest CI/logs and clean hosted package dry-run evidence.

## Decision Log

- 2026-05-14: Chose per-route concurrency throttling as the next middleware
  slice because it complements rate limiting, protects the production HTTP
  bridge from in-flight overload, and does not require adapter/product
  decisions.

## Handoff

HTTP route concurrency throttling is complete locally. Routes can configure a
typed per-route `concurrency_limit` / `concurrencyLimit` / `throttle` block,
the settings codec round-trips the limit, runtime enforcement rejects excess
in-flight requests before immediate or WAMP-backed dispatch, and slots are
released when immediate handlers or pending HTTP calls complete. Hosted
evidence is clean for pushed commit `18a1563`.

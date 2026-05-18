# Exec Plan: HTTP Route Access Log Middleware

Status: complete
Owner: Codex
Created: 2026-05-14
Last updated: 2026-05-14

## Goal

Complete the HTTP route middleware readiness slice by adding a typed,
route-scoped access logging hook that emits structured request start and
completion events without logging sensitive headers by default.

## Scope

- In scope: typed route access-log settings, config loader aliases, settings
  codec round-trip, runtime start/completion events, duration/status/outcome
  metadata, safe optional query/header inclusion, and focused tests.
- Out of scope: external log sinks, formatting backends, sampling, body logging,
  per-adapter pipelines, static file adapters, reverse proxy adapters, and
  distributed tracing exporters.

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
  `18a1563`.

## Plan

1. Add typed `HttpRouteAccessLogSettings` to the HTTP route action surface.
2. Parse `access_log` / `accessLog` / `logging` config with safe defaults and
   encode it through `RouterSettingsCodec`.
3. Emit structured access start/completion events for configured HTTP routes.
4. Include duration, outcome, and status when available; redact sensitive
   headers when optional header logging is enabled.
5. Add focused config-loader/codec and runtime regressions.
6. Run focused tests and `bin/verify`.

## Verification

- `bin/test-fast` passed on 2026-05-14 before edits.
- `dart test packages/connectanum_router/test/router_config_loader_test.dart -n "middleware settings"` passed.
- `dart test packages/connectanum_router/test/router_runtime_test.dart -n "logs HTTP route access"` passed.
- `git diff --check` passed.
- `bin/verify` passed on 2026-05-14.
- GitHub PR CI #25862587507 passed on `7904822` with `Fast Checks` and
  `Full Verify` green.
- GitHub Dart Package Publish Dry Run #25862587325 passed on `7904822`.
- `bin/audit-github-deployment-chain --branch codex/post-rc-production-readiness --run-limit 1 --require-clean-latest-ci --require-clean-latest-ci-logs --require-clean-dart-package-publish-dry-run`
  passed with clean latest CI/logs and clean hosted package dry-run evidence.

## Decision Log

- 2026-05-14: Chose route-scoped access logging because rate limiting and
  concurrency throttling are already complete; logging is the remaining
  middleware readiness item that does not require a larger adapter or product
  policy decision.

## Handoff

HTTP route access logging is complete locally. Routes can configure a typed
`access_log` / `accessLog` / `logging` block, the settings codec round-trips
the setting, the Dart router binding emits structured route access start and
completion events, optional query/header logging is opt-in, sensitive headers
are redacted, and completion events include duration, outcome, and status when
available. Hosted evidence is clean for pushed commit `7904822`.

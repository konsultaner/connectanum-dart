# Exec Plan: HTTP Publish Route Action

Status: complete
Owner: Codex
Created: 2026-05-14
Last updated: 2026-05-14

## Goal

Make configured HTTP `publish` routes usable for release readiness, so an HTTP
endpoint can publish a standardized request context onto a configured WAMP topic
through the router internal-session path.

## Scope

- In scope: Dart config loading/codec coverage, native config generation for
  request enqueueing, synthetic router runtime dispatch, and acknowledged
  publish responses.
- Out of scope: static file serving, reverse proxy adapters, custom isolate
  handler pipelines, and bespoke request-body-to-event schema options.

## Files Expected To Change

- `packages/connectanum_router/lib/src/router/router_instance/router_controller.dart`
- `packages/connectanum_router/lib/src/router/router_instance/router_binding.dart`
- `packages/connectanum_router/test/router_config_loader_test.dart`
- `packages/connectanum_router/test/router_json_test.dart`
- `packages/connectanum_router/test/router_runtime_test.dart`
- `ROADMAP.md`
- `docs/project_state.md`

## Preconditions

- `bin/test-fast` passed on 2026-05-14 before edits.
- No product decision is needed for the first slice because `publish` and
  `topic` already exist in the public HTTP route action surface, and the router
  internal session already enforces WAMP publish authorization.

## Plan

1. Wire `HttpRouteActionType.publish` through native HTTP route config as a
   translation entry so native HTTP requests are enqueued for Dart handling.
2. Intercept matched HTTP publish routes in the Dart binding and publish the
   standard HTTP request context to the configured WAMP topic using an
   acknowledged internal-session publish.
3. Return a structured `202 Accepted` JSON response after the publish succeeds.
4. Add focused config-loader, native-config JSON, and runtime dispatch
   regressions.
5. Run focused tests and `bin/verify`.

## Verification

- `bin/test-fast`
- `dart test packages/connectanum_router/test/router_config_loader_test.dart -n "publish routes"`
- `dart test packages/connectanum_router/test/router_json_test.dart -n "publish routes"`
- `dart test packages/connectanum_router/test/router_runtime_test.dart -n "publish actions"`
- `bin/verify`
- GitHub PR CI #25856957962 passed on `5d8ff5b` with `Fast Checks` and
  `Full Verify` green.
- GitHub Dart Package Publish Dry Run #25856957965 passed on `5d8ff5b`.
- `bin/audit-github-deployment-chain --branch codex/post-rc-production-readiness --run-limit 1 --require-clean-latest-ci --require-clean-latest-ci-logs --require-clean-dart-package-publish-dry-run`
  passed with clean latest CI/logs and clean hosted package dry-run evidence.

## Decision Log

- 2026-05-14: Chose `publish` before broader file/custom-handler adapter work
  because it is already a parsed public route action and directly advances the
  policy-driven HTTP bridge topic-routing roadmap item without adding a new
  configuration concept.

## Handoff

`publish` routes now parse, encode to native translation entries for request
enqueueing, publish the standard HTTP request context through router internal
sessions, and return acknowledged `202` JSON responses. Commit `5d8ff5b` is
pushed to GitHub PR #79 with clean hosted CI/package dry-run/audit evidence.
Remaining policy-driven HTTP bridge work stays on file/custom-handler adapters,
middleware hooks, and configurable payload-shaping options.

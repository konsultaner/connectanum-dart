# Exec Plan: Realm Authorization Provider Model

Status: completed
Owner: Codex
Created: 2026-04-23
Last updated: 2026-04-23

## Goal

Replace the current isolate-local dynamic realm authorization hook with a
worker-safe, realm-scoped provider model that can be instantiated from checked-
in router settings, so remote-auth hardening has a production-usable
authorization surface instead of a test-only global callback.

## Scope

- In scope:
  - reproduce the current worker-path gap with a focused integration test
  - add a config-driven realm authorization provider definition and per-realm
    selection surface to router settings
  - make worker isolates instantiate configured authorization providers from
    serialized settings instead of relying on a single process-local object
  - expose the default worker entrypoint so custom worker bootstraps can
    register provider factories before delegating to the standard router worker
  - refresh project state and verification notes for the new milestone
- Out of scope:
  - redesign of remote authenticator challenge flows
  - HTTP bearer provider work, bench budgets, or transport feature changes
  - speculative authorization policy DSL work beyond the minimum production
    model needed for worker-safe realm authorization

## Files Expected To Change

- `packages/connectanum_router/lib/src/router/auth/authorization.dart`
- `packages/connectanum_router/lib/src/router/config/router_settings.dart`
- `packages/connectanum_router/lib/src/router/config/router_config_loader.dart`
- `packages/connectanum_router/lib/src/router/config/router_settings_codec.dart`
- `packages/connectanum_router/lib/src/router/config/router_settings_builder.dart`
- `packages/connectanum_router/lib/src/router/router_instance/router_worker.dart`
- `packages/connectanum_router/lib/src/router/router_instance/router_worker_session.dart`
- `packages/connectanum_router/lib/src/router/router_instance/router_controller.dart`
- `packages/connectanum_router/lib/src/router/router_instance/router_binding.dart`
- `packages/connectanum_router/test/authorization_test.dart`
- `packages/connectanum_router/test/authorization_integration_test.dart`
- `packages/connectanum_router/test/router_config_loader_test.dart`
- `docs/project_state.md`
- `docs/exec-plans/2026-04-23-realm-authorization-provider-model.md`

## Preconditions

- `bin/test-fast` is green before edits. Confirmed on 2026-04-23.
- Hosted GitHub validation is green through commit `e5d8752` on the current
  branch head.

## Plan

1. Add a focused integration repro that exercises authorization from a real
   worker-isolate router session instead of the existing in-process unit hook.
2. Introduce a realm-scoped authorization provider definition/factory model in
   router settings and make workers resolve providers from serialized config.
3. Expose the default worker entrypoint for custom bootstraps, preserve unit
   coverage for authorization ordering semantics, then run targeted auth/router
   tests and full `bin/verify`.

## Verification

- `bin/test-fast`
- `cd packages/connectanum_router && dart test test/authorization_test.dart test/authorization_integration_test.dart test/router_config_loader_test.dart -r expanded`
- `bin/verify`

## Decision Log

- 2026-04-23: Treat the current global `AuthorizationProviderRegistry` as an
  insufficient production surface because real router authorization runs in
  spawned worker isolates, not only in the isolate that registered the
  provider object.
- 2026-04-23: Prefer a config-driven provider definition per realm over a new
  ad hoc callback parameter, because router settings already provide the
  canonical serialized surface workers receive at startup.
- 2026-04-23: Keep the legacy in-process `AuthorizationProviderRegistry` as a
  compatibility fallback for single-isolate uses and direct unit tests, but
  treat configured provider factories plus worker resolution as the production
  path for real router sessions.

## Handoff

- Completed on 2026-04-23.
- The worker-path regression was reproduced first: a live router session in a
  spawned worker isolate ignored an authorization provider registered only in
  the main isolate and incorrectly allowed an acknowledged `PUBLISH`.
- The fix adds serialized `authorization_providers` definitions at the router
  level, per-realm `authorization_provider` selection, a worker-local provider
  cache, and a public `defaultRouterWorkerEntryPoint(...)` that custom worker
  bootstraps can delegate to after registering factories.
- Focused auth/config tests and full `bin/verify` passed locally on the final
  working tree.

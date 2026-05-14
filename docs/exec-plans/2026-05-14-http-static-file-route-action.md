# HTTP Static File Route Action

Status: complete locally; hosted evidence pending after push
Owner: Codex
Created: 2026-05-14
Last updated: 2026-05-14

## Goal

Make the existing `HttpRouteActionType.file` route surface operational for
release readiness. A route configured with `type: file` and `directory` should
serve files directly from the router binding, while preserving the native HTTP
route gate for path/method/protocol/auth middleware and rejecting attempts to
escape the configured directory.

## Scope

- Wire `file` HTTP route actions into native route config as an internal
  enqueue target so native HTTP requests still pass through the existing route
  matcher and transport gates.
- Handle matched file routes in `RouterBinding` before WAMP dispatch.
- Resolve requested paths relative to the configured directory, reject unsafe
  path segments and symlink escapes, infer common content types, and apply
  `cache_control`.
- Cover config parsing/codec, native config generation, binding-level serving,
  and native runtime HTTP round-trip behavior.

## Out Of Scope

- PHP-FPM/FastCGI and reverse-proxy adapters.
- Directory listings, SPA fallback/index rewriting, range requests, ETags, or
  conditional requests.
- Public pub.dev publishing and release-tag operations.

## Verification

- 2026-05-14: Pre-edit `bin/test-fast` passed on Darwin arm64.
- 2026-05-14: Focused route/config/runtime tests passed:
  `dart test packages/connectanum_router/test/router_config_loader_test.dart
  packages/connectanum_router/test/router_json_test.dart
  packages/connectanum_router/test/router_runtime_test.dart -r expanded`.
- 2026-05-14: Focused native HTTP route test passed:
  `dart test packages/connectanum_router/test/router_integration_native_test.dart
  --name "serves configured HTTP file routes" -r expanded`.
- 2026-05-14: `bin/verify` passed on Darwin arm64.

## Next Step

Commit and push this implementation together with the project-state updates,
then watch PR CI, hosted package dry-run, and the deployment-chain audit for
the pushed commit.

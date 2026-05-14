# HTTP Static File Route Action

Status: complete
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
- 2026-05-14: Committed as `0eb89aa` and pushed to GitHub PR #79.
- 2026-05-14: PR-triggered GitHub CI #25868250887 passed on `0eb89aa`
  with `Fast Checks` and `Full Verify` green.
- 2026-05-14: PR-triggered Dart Package Publish Dry Run #25868251230 passed
  on `0eb89aa`.
- 2026-05-14: `bin/audit-github-deployment-chain --branch
  codex/post-rc-production-readiness --run-limit 1
  --require-clean-latest-ci --require-clean-latest-ci-logs
  --require-clean-dart-package-publish-dry-run` passed with clean latest CI
  logs and clean hosted package dry-run evidence. PR #79 remains blocked only
  by review/merge requirements before release-branch promotion.

## Next Step

Select the next release-readiness implementation slice from `ROADMAP_NEXT.md`
and `ROADMAP.md`. The remaining external gate for this slice is review/merge
of PR #79 before release-branch promotion.

## Handoff

HTTP `file` routes are operational through the normal router route matcher and
serve from the configured directory before WAMP dispatch. The implementation
validates configuration, rejects path traversal and symlink escapes, infers
common content types, applies cache-control headers, and has local plus hosted
verification evidence on `0eb89aa`.

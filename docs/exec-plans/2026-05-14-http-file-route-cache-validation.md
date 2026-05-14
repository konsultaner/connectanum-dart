# HTTP File Route Cache Validation

Status: active
Owner: Codex
Created: 2026-05-14
Last updated: 2026-05-14

## Goal

Tighten configured HTTP `file` routes for static-asset production readiness by
adding validator metadata and conditional request handling.

## Scope

- Add deterministic weak `ETag` and `Last-Modified` headers to successful
  router-served file responses.
- Honor `If-None-Match` and `If-Modified-Since` for `GET` and `HEAD` file
  route requests with `304 Not Modified` and no response body.
- Cover binding-level synthetic requests and native HTTP runtime round-trip
  behavior.

## Out Of Scope

- Byte range requests and multipart responses.
- Directory index fallback, directory listings, and rewrite rules.
- FastCGI, reverse proxy, or custom handler adapter routing.
- Public pub.dev publishing and release-tag operations.

## Verification

- 2026-05-14: Pre-edit `bin/test-fast` passed on Darwin arm64.
- 2026-05-14: Focused binding-level file route test passed:
  `dart test packages/connectanum_router/test/router_runtime_test.dart
  --plain-name "serves configured HTTP file routes directly from the binding"
  -r expanded`.
- 2026-05-14: Focused native HTTP route test passed:
  `dart test packages/connectanum_router/test/router_integration_native_test.dart
  --name "serves configured HTTP file routes" -r expanded`.
- 2026-05-14: `dart analyze packages/connectanum_router` passed.
- 2026-05-14: `git diff --check` passed.
- 2026-05-14: Full local `bin/verify` passed on Darwin arm64.

## Next Step

Commit with the bundled project-state updates, push, and audit the GitHub
deployment chain.

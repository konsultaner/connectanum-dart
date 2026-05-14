# HTTP File Route HEAD And Content Length

Status: active
Owner: Codex
Created: 2026-05-14
Last updated: 2026-05-14

## Goal

Tighten the newly operational HTTP `file` route behavior for release
readiness. File routes should return deterministic `Content-Length` headers and
honor `HEAD` requests by returning the same metadata as `GET` without sending a
file body.

## Scope

- Add `Content-Length` to successful router-served static file responses.
- Treat `HEAD` file-route requests as metadata-only responses with an empty
  body while preserving status and headers.
- Cover binding-level synthetic requests and native HTTP runtime round-trip
  behavior.

## Out Of Scope

- Range requests, ETags, conditional requests, directory index fallback, and
  cache validators.
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

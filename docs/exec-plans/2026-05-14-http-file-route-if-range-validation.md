# HTTP File Route If-Range Validation

Status: active
Owner: Codex
Created: 2026-05-14
Last updated: 2026-05-14

## Goal

Tighten configured HTTP `file` route byte-range behavior by validating
`If-Range` consistently with HTTP validator semantics before serving partial
responses.

## Scope

- Keep `If-Range` date validators working for unchanged files.
- Treat weak entity tags as non-matching for `If-Range`, including the weak
  `ETag` values emitted by the current file route implementation.
- Fall back to a full `200 OK` file response when `If-Range` does not match.
- Cover binding-level synthetic requests and native HTTP runtime round-trip
  behavior.

## Out Of Scope

- Changing the file route ETag format from weak to strong.
- Multipart byte-range responses.
- Additional static-file adapter features such as directory indexes,
  reverse-proxy stubs, or FastCGI routing.

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
- 2026-05-14: Committed as `b4abb76` and pushed to GitHub PR #79.
- 2026-05-14: Push-triggered GitHub CI #25877601918 passed; push-triggered
  Dart Package Publish Dry Run #25877601856 passed; PR-triggered Dart Package
  Publish Dry Run #25877604674 passed.
- 2026-05-14: PR-triggered GitHub CI #25877605262 failed twice in `Full
  Verify` while loading the Chrome/Dart2Wasm websocket test with
  `package:test` browser-manager `Cannot add stream while adding stream`.
- 2026-05-14: Added a narrow `bin/test-all` retry for only that browser
  test-runner startup signature; the browser test remains required and normal
  test failures still fail immediately.
- 2026-05-14: Pre-edit `bin/test-fast` passed before the CI retry-wrapper
  change.
- 2026-05-14: `bash -n bin/test-all` passed.
- 2026-05-14: Focused browser websocket test passed from
  `packages/connectanum_client` after `ensure_chrome_env`:
  `dart test test/transport/websocket/websocket_transport_web_test.dart
  -p chrome --timeout=5m --concurrency=1`.
- 2026-05-14: Full local `bin/verify` passed on Darwin arm64 with the retry
  wrapper in place.

## Next Step

Commit the CI retry wrapper with the bundled project-state updates, push, and
audit the GitHub deployment chain.

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

## Next Step

Commit with the bundled project-state updates, push, and audit the GitHub
deployment chain.

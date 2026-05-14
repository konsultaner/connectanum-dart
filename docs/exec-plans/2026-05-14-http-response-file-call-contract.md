# Exec Plan: HTTP Response File Call Contract

Status: complete
Owner: Codex
Created: 2026-05-14
Last updated: 2026-05-14

## Goal

Close the HTTP call-contract coverage gap by making `sendFile` usable through
router-hosted HTTP routes and proving the helper response contract across Dart
runtime dispatch and the native HTTP runtime.

## Scope

- In scope: `HttpInvocationContext.sendFile` dispatch, native file response
  body encoding, helper-body mapping tests for bytes/json/file, native HTTP
  file response round-trip coverage, and removal of an unnecessary skip from
  the existing native HTTP response round-trip test.
- Out of scope: static-file route adapters, reverse proxy/FastCGI adapters,
  zero-copy sendfile descriptors, directory traversal policy, MIME inference,
  range requests, and public documentation beyond roadmap/project-state
  tracking.

## Files Expected To Change

- `packages/connectanum_router/lib/src/router/router_instance/router_binding.dart`
- `packages/connectanum_router/lib/src/native/runtime.dart`
- `packages/connectanum_router/test/router_runtime_test.dart`
- `packages/connectanum_router/test/router_integration_native_test.dart`
- `ROADMAP.md`
- `docs/project_state.md`

## Preconditions

- `bin/test-fast` passed on 2026-05-14 before edits.
- Previous pushed head `7904822` has clean hosted PR CI, hosted Dart package
  dry-run, and strict deployment-chain audit evidence.

## Plan

1. Map file response payloads from the HTTP call result into
   `NativeHttpResponseFile` instead of reporting them as unsupported.
2. Encode `NativeHttpResponseFile` bodies in the native Dart runtime so the
   existing native buffered HTTP send path can flush file contents.
3. Add Dart runtime coverage for bytes, JSON, and file response helper bodies.
4. Add native runtime coverage proving file responses reach an HTTP client.
5. Re-enable the existing native HTTP response round-trip test when only the
   native library is available, because it is unrelated to zero-copy publish
   forwarding.
6. Run focused tests and `bin/verify`.

## Verification

- `bin/test-fast` passed on 2026-05-14 before edits.
- `dart test packages/connectanum_router/test/router_runtime_test.dart -n "maps HTTP response helper bodies"` passed.
- `dart test packages/connectanum_router/test/router_integration_native_test.dart -n "serves file HTTP responses through native runtime"` passed.
- `dart test packages/connectanum_router/test/router_integration_native_test.dart -n "routes HTTP request through native runtime"` passed.
- `git diff --check` passed.
- `bin/verify` passed on 2026-05-14.
- GitHub PR CI #25864917191 passed on `53b4976` with `Fast Checks` and
  `Full Verify` green.
- GitHub Dart Package Publish Dry Run #25864917111 passed on `53b4976`.
- `bin/audit-github-deployment-chain --branch codex/post-rc-production-readiness --run-limit 1 --require-clean-latest-ci --require-clean-latest-ci-logs --require-clean-dart-package-publish-dry-run`
  passed with clean latest CI/logs and clean hosted package dry-run evidence;
  PR #79 remains blocked only by review/merge requirements before release
  branch promotion.

## Decision Log

- 2026-05-14: Chose the file response call-contract gap because the public
  helper already existed but threw at dispatch time, while larger adapter
  pipeline work still needs product-level route semantics.

## Handoff

HTTP response file dispatch is complete locally. `sendFile` no longer falls
through to an unsupported response path, native HTTP clients receive file body
contents through the existing buffered send path, helper-body mapping now has
bytes/JSON/file runtime coverage, native file response round-trip coverage is
in place, and the existing native HTTP response round-trip test now runs
without requiring the zero-copy publish feature flag. Hosted CI, hosted package
dry-run, and strict deployment-chain audit evidence are clean for pushed commit
`53b4976`.

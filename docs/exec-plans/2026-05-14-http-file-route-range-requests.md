# HTTP File Route Range Requests

Status: complete
Owner: Codex
Created: 2026-05-14
Last updated: 2026-05-14

## Goal

Tighten configured HTTP `file` routes for static-asset production readiness by
supporting single byte-range requests with correct response metadata.

## Scope

- Advertise byte range support on successful file responses.
- Honor single `Range: bytes=...` requests for `GET` and `HEAD` with
  `206 Partial Content`, `Content-Range`, and range-specific `Content-Length`.
- Return `416 Range Not Satisfiable` with `Content-Range: bytes */<size>` for
  syntactically valid but unsatisfiable byte ranges.
- Keep conditional `304 Not Modified` behavior ahead of range handling.
- Cover binding-level synthetic requests and native HTTP runtime round-trip
  behavior.

## Out Of Scope

- Multipart range responses.
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
- 2026-05-14: Full local `bin/verify` passed.
- 2026-05-14: Committed as `74293b9` and pushed to GitHub PR #79.
- 2026-05-14: Push-triggered GitHub CI #25875434489 passed with
  `Fast Checks` and `Full Verify` green.
- 2026-05-14: Push-triggered Dart Package Publish Dry Run #25875434528
  passed.
- 2026-05-14: PR-triggered latest GitHub CI #25875438471 passed with
  `Fast Checks` and `Full Verify` green.
- 2026-05-14: PR-triggered latest Dart Package Publish Dry Run #25875438511
  passed.
- 2026-05-14: Deployment-chain audit passed with clean latest CI/logs and
  clean hosted Dart package dry-run evidence:
  `bin/audit-github-deployment-chain --branch codex/post-rc-production-readiness
  --run-limit 1 --require-clean-latest-ci --require-clean-latest-ci-logs
  --require-clean-dart-package-publish-dry-run`.

## Next Step

PR #79 still needs review/merge before release-branch promotion. No further
range-request work is planned unless consumer use finds a correctness issue.

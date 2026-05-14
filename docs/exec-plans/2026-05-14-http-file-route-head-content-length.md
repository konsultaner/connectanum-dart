# HTTP File Route HEAD And Content Length

Status: complete
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
- 2026-05-14: Committed as `90cb23d` and pushed to GitHub PR #79.
- 2026-05-14: Push-triggered GitHub CI #25870513225 passed on `90cb23d`
  with `Fast Checks` and `Full Verify` green.
- 2026-05-14: Push-triggered Dart Package Publish Dry Run #25870513185
  passed on `90cb23d`.
- 2026-05-14: PR-triggered latest GitHub CI #25870523008 passed on
  `90cb23d` with `Fast Checks` and `Full Verify` green; PR-triggered latest
  Dart Package Publish Dry Run #25870523053 also passed.
- 2026-05-14: `bin/audit-github-deployment-chain --branch
  codex/post-rc-production-readiness --run-limit 1
  --require-clean-latest-ci --require-clean-latest-ci-logs
  --require-clean-dart-package-publish-dry-run` passed with clean latest CI
  jobs/logs and clean hosted package dry-run evidence. PR #79 remains blocked
  only by review/merge requirements before release-branch promotion.

## Next Step

Select the next release-readiness implementation slice from `ROADMAP_NEXT.md`
and `ROADMAP.md`. The remaining external gate for this slice is review/merge
of PR #79 before release-branch promotion.

## Handoff

Successful HTTP `file` route responses now include deterministic
`Content-Length`, and `HEAD` returns the same headers/status as `GET` without a
file body through both the router binding and native HTTP runtime path.

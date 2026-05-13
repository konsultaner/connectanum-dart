# Exec Plan: MCP Consumer CORS Error Session Smoke

Status: complete; hosted CI and deployment-chain evidence clean
Owner: Codex
Created: 2026-05-12
Last updated: 2026-05-12

## Goal

Prove router-hosted MCP browser clients can read auth and header-validation
failures through configured CORS policy, and that rejected Streamable HTTP
requests do not corrupt the active MCP session.

## Scope

- Keep MCP route auth failures in the Dart binding path so route-specific MCP
  CORS policy is available before responding.
- Extend the generated consumer package smoke with raw secure missing-bearer
  CORS checks for direct JSON and Streamable initialize.
- Add raw Streamable HTTP header-error checks for missing `Mcp-Method`,
  mismatched `Mcp-Name`, missing `Mcp-Param-TaskId`, and invalid
  `Mcp-Param-Note`, followed by a valid request proving the session still works.

## Verification

- Pre-change `bin/test-fast` passed on 2026-05-12.
- Focused pre-fix smoke reproduced missing CORS on secure direct JSON missing
  bearer: native listener-side transport auth returned only
  `WWW-Authenticate`.
- Focused
  `bash -lc 'source bin/common.sh; cd_repo_root; dart_workspace_bootstrap; run_mcp_consumer_package_smoke'`
  passed on 2026-05-12 after the implementation.
- `dart test packages/connectanum_router/test/http_route_transport_auth_test.dart`
  passed on 2026-05-12.
- `dart analyze packages/connectanum_router` passed on 2026-05-12.
- Full local `bin/verify` passed on 2026-05-12.
- Commit `59a8e79` (`fix: keep mcp auth failures cors-readable`) was pushed to
  both configured remotes on 2026-05-12.
- GitHub Actions `CI` run `25746825371` passed on `59a8e79`: `Fast Checks` and
  `Full Verify` completed successfully.
- GitHub Actions `Dart Package Publish Dry Run` run `25746825383` passed on
  `59a8e79` and covers the checked-out head.
- GitHub Actions `WAMP Profile Benchmarks` run `25746825412` passed on
  `59a8e79`.
- `bin/audit-github-deployment-chain --branch add-router --require-clean-latest-ci --require-clean-latest-ci-logs --show-dart-package-publish-dry-run --require-clean-dart-package-publish-dry-run`
  passed on 2026-05-12. The audit found latest CI clean, latest CI log scan
  clean, and a clean relevant Dart package publish dry-run.
- Strict deployment-chain audit still fails only known operator-side
  release-hardening gaps: branch protection/required checks are not configured,
  `.github/workflows/router-image.yml` is not yet visible from the default
  branch, and the router GHCR package is not visible.

## Handoff

Implementation is complete and pushed. Local verification, hosted CI, hosted
log scan, hosted publish dry-run, hosted WAMP profile benchmark workflow, and
the non-strict deployment-chain audit are clean for `59a8e79`. The only
remaining strict-audit gaps are operator-side release-hardening items.

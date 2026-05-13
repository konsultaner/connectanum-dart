# Exec Plan: MCP Client Direct JSON Ping Helper Smoke

Status: complete; hosted CI and deployment-chain evidence clean
Owner: Codex
Created: 2026-05-13
Last updated: 2026-05-13

## Goal

Make lifecycle-free router-hosted MCP `ping` practical through the public
client helper API, including active Streamable HTTP sessions and
bearer-protected routes.

## Scope

- Add an explicit direct JSON mode to `McpStreamableHttpClient.ping(...)` so
  consumers can probe a router-hosted MCP endpoint without sending or mutating
  Streamable HTTP session state.
- Extend client tests to prove direct JSON `ping` omits `MCP-Session-Id` and
  `Last-Event-ID` while a Streamable session is active.
- Extend the generated neutral consumer package smoke so active Streamable
  sessions can use direct JSON `ping`, and protected routes reject missing or
  invalid bearer credentials for that helper path.
- Keep private downstream application names and local paths out of checked-in
  docs and generated package metadata.

## Files Expected To Change

- `packages/connectanum_client/lib/src/mcp/streamable_http_client.dart`
- `packages/connectanum_client/test/mcp/streamable_http_client_test.dart`
- `bin/common.sh`
- `docs/project_state.md`
- `docs/exec-plans/2026-05-13-mcp-client-direct-json-ping-helper-smoke.md`

## Preconditions

- Pre-change `bin/test-fast` passed on 2026-05-13.
- Router direct JSON `ping` support is complete and hosted-clean at branch
  checkpoint `e156708`.

## Plan

1. Add a `directJson` option to the public `ping(...)` helper that forces a
   direct JSON POST and suppresses Streamable session headers.
2. Pin the header/session behavior in the client fake-endpoint test.
3. Pin the active-session and protected-route behavior in the generated
   consumer package smoke.
4. Run focused tests, full local verification, then push and watch hosted
   evidence.

## Verification

- Pre-change `bin/test-fast` passed on 2026-05-13.
- `dart format packages/connectanum_client/lib/src/mcp/streamable_http_client.dart packages/connectanum_client/test/mcp/streamable_http_client_test.dart`
  passed with no file changes after formatting.
- `bash -n bin/common.sh` passed on 2026-05-13.
- Focused `dart test packages/connectanum_client/test/mcp/streamable_http_client_test.dart`
  passed on 2026-05-13.
- Focused
  `bash -lc 'source bin/common.sh; cd_repo_root; dart_workspace_bootstrap; run_mcp_consumer_package_smoke'`
  passed on 2026-05-13.
- Full local `bin/verify` passed on 2026-05-13.
- Commit `c4302db` (`mcp: add direct json ping helper`) was pushed to both
  configured remotes.
- GitHub `CI` run `25772595323` completed successfully for `c4302db` with
  `Fast Checks` and `Full Verify` green.
- GitHub `WAMP Profile Benchmarks` run `25772595350` completed successfully
  for `c4302db`.
- GitHub `Dart Package Publish Dry Run` run `25772595346` completed
  successfully and covers the checked-out head.
- `bin/audit-github-deployment-chain --branch add-router --require-clean-latest-ci --require-clean-latest-ci-logs --show-dart-package-publish-dry-run --require-clean-dart-package-publish-dry-run`
  passed with clean latest CI, clean hosted CI logs, and a clean relevant Dart
  package publish dry-run.
- Strict deployment-chain audit still fails only known operator-side
  release-hardening gaps: branch protection/required checks are absent,
  `.github/workflows/router-image.yml` is not yet visible from the default
  branch through the Actions API, and `ghcr.io/konsultaner/connectanum-router`
  is not visible in GitHub Packages.

## Decision Log

- 2026-05-13: Chose this slice because the router already supports
  lifecycle-free direct JSON `ping`, but the public client helper still lacked
  a direct JSON mode that suppresses active Streamable session headers.

## Handoff

Implementation is pushed. Focused local checks, full local verification,
hosted CI, WAMP benchmark workflow, package publish dry-run, hosted CI log
scan, and the non-strict deployment-chain audit are clean for `c4302db`.

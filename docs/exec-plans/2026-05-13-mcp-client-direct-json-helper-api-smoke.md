# Exec Plan: MCP Client Direct JSON Helper API Smoke

Status: complete; hosted CI and deployment-chain evidence clean
Owner: Codex
Created: 2026-05-13
Last updated: 2026-05-13

## Goal

Make lifecycle-free router-hosted MCP direct JSON access explicit in the
public client API for generic requests, notifications, and JSON-RPC batches,
then prove the helpers from a neutral generated consumer package.

## Scope

- Add public `McpStreamableHttpClient` helpers that force direct JSON POST
  semantics and suppress Streamable HTTP session headers.
- Reuse the direct request helper from the existing Connectanum direct method
  helper to keep header/session behavior centralized.
- Extend client tests to prove direct request, batch, and notification helpers
  remain lifecycle-free while a Streamable HTTP session is active.
- Extend the generated neutral consumer package smoke to use the direct helper
  API for generic tool/meta requests, batches, notifications, pub/sub batches,
  resource/prompt batches, and bearer-protected rejection checks.
- Keep private downstream application names and local paths out of checked-in
  docs and generated package metadata.

## Files Expected To Change

- `packages/connectanum_client/lib/src/mcp/streamable_http_client.dart`
- `packages/connectanum_client/test/mcp/streamable_http_client_test.dart`
- `bin/common.sh`
- `docs/project_state.md`
- `docs/exec-plans/2026-05-13-mcp-client-direct-json-helper-api-smoke.md`

## Preconditions

- Pre-change `bin/test-fast` passed on 2026-05-13.
- Client direct JSON `ping` helper work is complete and hosted-clean at branch
  checkpoint `c4302db`.

## Plan

1. Add direct request, notification, and batch helper APIs on
   `McpStreamableHttpClient`.
2. Pin lifecycle-free header/session behavior in focused client tests.
3. Switch representative generated consumer smoke coverage from manual
   `streamable/includeSession` flag pairs to the direct helper API.
4. Run focused checks, full local verification, then push and watch hosted
   evidence.

## Verification

- Pre-change `bin/test-fast` passed on 2026-05-13.
- `dart format packages/connectanum_client/lib/src/mcp/streamable_http_client.dart packages/connectanum_client/test/mcp/streamable_http_client_test.dart`
  passed on 2026-05-13.
- `bash -n bin/common.sh` passed on 2026-05-13.
- Focused `dart test packages/connectanum_client/test/mcp/streamable_http_client_test.dart`
  passed on 2026-05-13.
- Focused
  `bash -lc 'source bin/common.sh; cd_repo_root; dart_workspace_bootstrap; run_mcp_consumer_package_smoke'`
  passed on 2026-05-13.
- Full local `bin/verify` passed on 2026-05-13.
- Commit `09c5ce7` (`mcp: add direct json helper api`) was pushed to both
  configured remotes.
- GitHub `CI` run `25774096844` completed successfully for `09c5ce7` with
  `Fast Checks` and `Full Verify` green.
- GitHub `WAMP Profile Benchmarks` run `25774096845` completed successfully
  for `09c5ce7`.
- GitHub `Dart Package Publish Dry Run` run `25774096833` completed
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

- 2026-05-13: Chose this slice because the router and smokes already support
  lifecycle-free direct JSON access, but generic consumer code still had to
  remember paired `streamable: false` and `includeSession: false` flags for raw
  direct requests, notifications, and batches.

## Handoff

Implementation is pushed. Focused local checks, full local verification,
hosted CI, WAMP benchmark workflow, package publish dry-run, hosted CI log
scan, and the non-strict deployment-chain audit are clean for `09c5ce7`.

# Exec Plan: MCP Client Package Auth Grant Smoke

Status: complete; hosted CI and deployment-chain evidence clean
Owner: Codex
Created: 2026-05-10
Last updated: 2026-05-10

## Goal

Make the standalone MCP client-only consumer smoke use the same full HTTP auth
grant client construction path as the router-hosted and generated consumer
smokes, so successful secure Streamable HTTP setup is proven without copying a
raw access-token string into the public package smoke.

## Scope

- In scope: `bin/common.sh` generated MCP client-only consumer smoke.
- Out of scope: runtime auth behavior changes, router-hosted endpoint behavior,
  and intentionally rejected-token probes that still need raw bearer clients.

## Files Expected To Change

- `bin/common.sh`
- `docs/project_state.md`
- `docs/exec-plans/2026-05-10-mcp-client-package-auth-grant-smoke.md`

## Preconditions

- Serena project onboarding is complete for this repository.
- Pre-change `bin/test-fast` must pass before editing the generated smoke.

## Plan

1. Confirm worktree state and run the pre-change fast gate.
2. Change the client-only generated smoke to construct its successful
   `McpStreamableHttpClient` with `McpStreamableHttpClient.withAuthGrant(...)`
   and a complete `ConnectanumHttpAuthGrant`.
3. Keep the fake endpoint's bearer header assertion unchanged so the smoke
   still proves the grant maps to the expected HTTP `Authorization` header.
4. Run the focused generated smoke, `bin/test-fast`, and `bin/verify`; then
   push and collect hosted deployment-chain evidence.

## Verification

- Pre-change `bin/test-fast` passed on 2026-05-10.
- Focused `bash -n bin/common.sh` passed on 2026-05-10.
- Focused `bash -lc 'source bin/common.sh; run_mcp_client_package_smoke'`
  passed on 2026-05-10.
- Post-change `bin/test-fast` passed on 2026-05-10.
- Full local `bin/verify` passed on 2026-05-10 after clearing a stale native
  runtime lock left by the first verify attempt.
- Commit `ae7c02e` (`test: use auth grants in mcp client smoke`) is pushed to
  both remotes.
- GitHub `CI` run `25637060551` completed successfully for `ae7c02e` with
  `Fast Checks` (4m30s) and `Full Verify` (6m17s) green; the hosted CI log
  scan was clean.
- GitHub `Dart Package Publish Dry Run` run `25635686773` remains clean and
  relevant because no publish-sensitive package inputs changed after
  `90a27ca`.
- Deployment-chain audit passed with clean latest CI, clean hosted CI logs, and
  a clean relevant Dart package publish dry-run. Strict audit still reports
  only known operator-side release-hardening gaps: branch protection/required
  checks are absent, `.github/workflows/router-image.yml` is not yet visible
  from the default branch through the Actions API, and
  `ghcr.io/konsultaner/connectanum-router` is not visible in GitHub Packages.

## Decision Log

- 2026-05-10: Continue the auth-grant migration at the standalone client-only
  smoke layer because it was the remaining successful generated package smoke
  that still constructed the Streamable client from a raw bearer string.

## Handoff

Implementation, focused and full local verification, hosted CI, relevant
package publish dry-run, and deployment-chain evidence are complete for this
slice.

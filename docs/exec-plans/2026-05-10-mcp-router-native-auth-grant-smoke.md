# Exec Plan: MCP Router Native Auth Grant Smoke

Status: complete; hosted CI and deployment-chain evidence clean
Owner: Codex
Created: 2026-05-10
Last updated: 2026-05-10

## Goal

Make router-native MCP integration coverage use full HTTP auth bridge grants for
successful secure Streamable HTTP clients, matching the public consumer API path
while preserving raw bearer headers only for direct HTTP and rejected-principal
assertions.

## Scope

- In scope: `packages/connectanum_router/test/router_integration_native_test.dart`
  secure MCP Streamable client setup and the public MCP README guidance for
  protected routes.
- Out of scope: router runtime behavior changes, HTTP auth protocol changes,
  and generated consumer package smoke changes already covered by the prior
  exec plan.

## Files Expected To Change

- `packages/connectanum_router/test/router_integration_native_test.dart`
- `packages/connectanum_mcp/README.md`
- `docs/project_state.md`
- `docs/exec-plans/2026-05-10-mcp-router-native-auth-grant-smoke.md`

## Preconditions

- Serena project onboarding is complete for this repository.
- Pre-change `bin/test-fast` must pass before editing the integration test.

## Plan

1. Confirm the current branch and pre-change fast gate are clean.
2. Convert successful secure router-native MCP clients from raw access-token
   strings to `ConnectanumHttpAuthGrant` plus
   `McpStreamableHttpClient.withAuthGrant`.
3. Keep explicit bearer headers for direct HTTP assertions and
   rejected-principal session isolation probes.
4. Run focused router-native MCP integration coverage, `bin/test-fast`, and
   `bin/verify`; then push and collect hosted deployment-chain evidence.

## Verification

- Pre-change `bin/test-fast` passed on 2026-05-10.
- Focused `dart test packages/connectanum_router/test/router_integration_native_test.dart -p vm`
  passed on 2026-05-10.
- Post-change `bin/test-fast` passed on 2026-05-10.
- Full local `bin/verify` passed on 2026-05-10.
- Commit `90a27ca` (`test: use auth grants in router mcp integration`) is
  pushed to both remotes.
- GitHub `CI` run `25635686770` completed successfully for `90a27ca` with
  `Fast Checks` (4m19s) and `Full Verify` (6m11s) green; the hosted CI log
  scan was clean.
- GitHub `Dart Package Publish Dry Run` run `25635686773` completed
  successfully for `90a27ca` with `Publish Dry Run` (20s) green and covers the
  checked-out head.
- GitHub `WAMP Profile Benchmarks` run `25635686778` completed successfully for
  `90a27ca` with `Linux WAMP profile gates` (7m55s) green.
- Deployment-chain audit passed with clean latest CI, clean hosted CI logs, and
  a clean relevant Dart package publish dry-run. Strict audit still reports
  only known operator-side release-hardening gaps: branch protection/required
  checks are absent, `.github/workflows/router-image.yml` is not yet visible
  from the default branch through the Actions API, and
  `ghcr.io/konsultaner/connectanum-router` is not visible in GitHub Packages.

## Decision Log

- 2026-05-10: Continue the MCP auth-grant migration at the router-native
  integration layer because it is the remaining successful secure MCP coverage
  still constructing Streamable clients from copied access-token strings.

## Handoff

Implementation, full local verification, hosted CI, WAMP benchmark, package
publish dry-run, and deployment-chain evidence are complete for this slice.

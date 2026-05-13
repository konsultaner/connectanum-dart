# Exec Plan: MCP Example Auth Grant Smoke

Status: complete; hosted CI and deployment-chain evidence clean
Owner: Codex
Created: 2026-05-10
Last updated: 2026-05-10

## Context

The public router-hosted MCP example already exercises protected direct JSON and
Streamable HTTP MCP flows, but its successful secure clients still copied the
HTTP auth bridge access token into `McpStreamableHttpClient.withBearerToken`.
Consumer applications now have `McpStreamableHttpClient.withAuthGrant`, so the
public example should prove the safer grant handoff directly and avoid teaching
manual token-field plumbing where a complete grant is available.

## Implementation Plan

1. Update successful secure router-hosted MCP example clients to use
   `McpStreamableHttpClient.withAuthGrant` with `ConnectanumHttpAuthGrant`.
2. Keep raw bearer-token clients only for negative rotated/revoked-token probes,
   where the example intentionally tests rejected token strings.
3. Run the focused router-hosted MCP example smoke and the neutral generated
   consumer package smoke path that launches it.
4. Run `bin/test-fast` after the change and `bin/verify` before handoff.
5. Bundle the previous hosted-evidence docs-only updates with this
   implementation commit.

## Verification

- Pre-change `bin/test-fast` passed on 2026-05-10.
- Focused `bash -lc 'source bin/common.sh;
  run_router_hosted_mcp_example_smoke'` passed after switching the public
  example secure success flows to `withAuthGrant`.
- Focused `bash -lc 'source bin/common.sh; run_mcp_consumer_package_smoke'`
  passed after the public example change.
- Post-change `bin/test-fast` passed on 2026-05-10.
- Full local `bin/verify` passed on 2026-05-10.
- Commit `30b834a` (`test: use mcp auth grants in router example`) was
  pushed to `origin/add-router` and `github/add-router` on 2026-05-10.
- GitHub `CI` run `25633616482` completed successfully for `30b834a` with
  `Fast Checks` (4m26s) and `Full Verify` (6m07s) green, and the hosted CI log
  scan was clean.
- GitHub `Dart Package Publish Dry Run` run `25633616452` completed
  successfully for `30b834a` and covers the checked-out head.
- GitHub `WAMP Profile Benchmarks` run `25633616456` completed successfully
  for `30b834a` with `Linux WAMP profile gates` green (7m56s).
- Deployment-chain audit passed on 2026-05-10 with clean latest CI, clean
  hosted CI logs, and clean Dart package publish dry-run evidence.
- Strict deployment-chain audit still reports only known operator-side
  release-hardening gaps: branch protection/required status checks are absent,
  `.github/workflows/router-image.yml` is not yet visible from the default
  branch through the Actions API, and
  `ghcr.io/konsultaner/connectanum-router` is not visible in GitHub Packages.

## Decision Log

- Protocol-version compatibility checks for the secure endpoint now use the
  auth grant constructor too, so both supported and rejected Streamable
  protocol-version paths prove the grant handoff.
- Negative rotated/revoked checks still use `withBearerToken` because they are
  intentionally asserting behavior for stale raw bearer strings after a grant
  refresh or revoke.

## Handoff

Implementation, full local verification, push, and hosted CI/deployment-chain
evidence are complete. Strict audit gaps remain operator-side
release-hardening work.

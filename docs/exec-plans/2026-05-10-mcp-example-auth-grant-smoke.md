# Exec Plan: MCP Example Auth Grant Smoke

Status: local verification complete; push and hosted evidence pending
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

## Decision Log

- Protocol-version compatibility checks for the secure endpoint now use the
  auth grant constructor too, so both supported and rejected Streamable
  protocol-version paths prove the grant handoff.
- Negative rotated/revoked checks still use `withBearerToken` because they are
  intentionally asserting behavior for stale raw bearer strings after a grant
  refresh or revoke.

## Handoff

Implementation and full local verification are complete. Push and hosted
deployment-chain evidence remain pending.

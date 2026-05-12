# Exec Plan: MCP Consumer Secure Protocol Version Smoke

Status: complete locally; hosted CI pending
Owner: Codex
Created: 2026-05-12
Last updated: 2026-05-12

## Goal

Make the generated router-hosted MCP consumer package smoke prove that
bearer-protected Streamable HTTP MCP routes support the same protocol-version
compatibility behavior as public routes when a downstream application uses only
public package APIs.

## Scope

- In scope: using `McpStreamableHttpClient.withAuthGrant` with older supported
  `MCP-Protocol-Version` values on the secure router-hosted MCP route.
- In scope: proving secure initialize negotiates back to
  `McpStreamableHttpClient.latestProtocolVersion`, can ping, can delete the
  Streamable session, and clears session/cursor state.
- In scope: proving an unsupported protocol-version header on the secure route
  returns HTTP 400 without leaking local Streamable session state.
- Out of scope: changing supported MCP protocol versions, auth policy, or route
  behavior.

## Files Expected To Change

- `bin/common.sh`
- `docs/project_state.md`
- `docs/exec-plans/2026-05-12-mcp-consumer-secure-protocol-version-smoke.md`
- Existing docs-only hosted-evidence updates from the deleted-session slice
  remain bundled with this implementation commit.

## Preconditions

- Serena project onboarding is complete for this repository.
- The latest pushed branch checkpoint `e2cd92d` has clean hosted CI and
  deployment-chain evidence; remaining strict-audit gaps are operator-side
  release-hardening items.
- Pre-change `bin/test-fast` passed on 2026-05-12.

## Plan

1. Reuse the generated consumer smoke's protocol-version compatibility helper
   for both public and secure MCP endpoints.
2. Add a small protocol-version client factory that can build either a public
   client or an auth-grant client while setting `defaultProtocolVersion`.
3. After issuing the secure ticket auth grant, run the supported-version and
   unsupported-version compatibility checks against the bearer-protected route.
4. Run focused generated smoke, `bin/test-fast`, and `bin/verify`; then push
   and collect hosted deployment-chain evidence.

## Verification

- Pre-change `bin/test-fast` passed on 2026-05-12.
- Focused `bash -n bin/common.sh` passed on 2026-05-12.
- Focused
  `bash -lc 'source bin/common.sh; run_mcp_consumer_package_smoke'` passed on
  2026-05-12.
- Post-change `bin/test-fast` passed on 2026-05-12.
- Full local `bin/verify` passed on 2026-05-12.
- Hosted CI and deployment-chain evidence are pending until the implementation
  commit is pushed.

## Decision Log

- 2026-05-12: Continue MCP downstream-readiness hardening on the neutral
  generated consumer package smoke. The public route already proved supported
  and unsupported Streamable HTTP protocol-version behavior; the secure route is
  the downstream-facing path for applications using HTTP auth grants and should
  prove the same compatibility through public client APIs.

## Handoff

Implementation is complete locally. Commit, push, hosted CI, and
deployment-chain evidence remain pending.

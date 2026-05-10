# Exec Plan: MCP Client Package Auth Grant Smoke

Status: full local verification complete; push and hosted evidence pending
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

## Decision Log

- 2026-05-10: Continue the auth-grant migration at the standalone client-only
  smoke layer because it was the remaining successful generated package smoke
  that still constructed the Streamable client from a raw bearer string.

## Handoff

Implementation plus focused, fast, and full local verification are complete.
Push and hosted deployment-chain evidence remain pending.

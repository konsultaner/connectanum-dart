# Exec Plan: MCP Client Package Auth Client Grant Smoke

Status: full local verification complete; push and hosted evidence pending
Owner: Codex
Created: 2026-05-10
Last updated: 2026-05-10

## Goal

Make the standalone MCP client-only consumer smoke obtain its bearer grant
through the public `ConnectanumHttpAuthClient` before opening a protected
Streamable HTTP MCP session, so the generated package smoke proves the full
consumer auth bridge flow instead of relying on a literal grant fixture.

## Scope

- In scope: `bin/common.sh` generated MCP client-only consumer smoke and its
  fake auth/MCP endpoint.
- Out of scope: router runtime auth behavior, package API changes, and negative
  raw-bearer probes in other smokes.

## Files Expected To Change

- `bin/common.sh`
- `docs/project_state.md`
- `docs/exec-plans/2026-05-10-mcp-client-package-auth-client-grant-smoke.md`

## Preconditions

- Serena project onboarding is complete for this repository.
- Pre-change `bin/test-fast` must pass before editing the generated smoke.

## Plan

1. Confirm the current MCP readiness context and run the pre-change fast gate.
2. Extend the generated client-only fake endpoint with a neutral `/auth`
   challenge/token flow.
3. Change the generated consumer app to call
   `ConnectanumHttpAuthClient.issueTicketToken(...)`, assert the parsed grant
   metadata, and pass that grant into `McpStreamableHttpClient.withAuthGrant`.
4. Run the focused generated smoke, `bin/test-fast`, and `bin/verify`; then
   push and collect hosted deployment-chain evidence.

## Verification

- Pre-change `bin/test-fast` passed on 2026-05-10.
- Focused `bash -n bin/common.sh` passed on 2026-05-10.
- Focused `bash -lc 'source bin/common.sh; run_mcp_client_package_smoke'`
  passed on 2026-05-10.
- Post-change `bin/test-fast` passed on 2026-05-10.
- Full local `bin/verify` passed on 2026-05-10.
- Push and hosted deployment-chain evidence remain pending.

## Decision Log

- 2026-05-10: Continue client-only package smoke hardening because the previous
  slice proved `withAuthGrant` with a full grant object, but did not prove that
  a generated consumer package can obtain that grant through the public HTTP
  auth client before opening the MCP session.

## Handoff

Implementation plus focused, fast, and full local verification are complete.
Push and hosted deployment-chain evidence remain pending.

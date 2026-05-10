# Exec Plan: MCP Consumer Package Auth Grant Smoke

Status: full local verification complete; push and hosted evidence pending
Owner: Codex
Created: 2026-05-10
Last updated: 2026-05-10

## Goal

Make the neutral generated consumer package smoke exercise the public
auth-grant handoff for successful secure Streamable HTTP MCP sessions, so
consumer applications can follow the grant-based API path without copying raw
access-token strings where a complete HTTP auth bridge grant is available.

## Scope

- In scope: generated consumer smoke coverage in `bin/common.sh` for
  router-hosted secure MCP sessions, session reuse isolation, and HTTP auth
  refresh/revoke flows.
- Out of scope: public API changes, router behavior changes, and docs-only
  example rewrites.

## Files Expected To Change

- `bin/common.sh`
- `docs/project_state.md`
- `docs/exec-plans/2026-05-10-mcp-consumer-package-auth-grant-smoke.md`

## Preconditions

- Serena project onboarding is complete for this repository.
- Pre-change `bin/test-fast` must pass before editing the smoke helper.

## Plan

1. Confirm the current branch and pre-change fast gate are clean.
2. Update the generated consumer package smoke so successful secure Streamable
   sessions accept `ConnectanumHttpAuthGrant`, while raw bearer access remains
   only for explicit rejected-token and cross-principal isolation probes.
3. Run the focused generated consumer package smoke, `bin/test-fast`, and
   `bin/verify`; then push and collect hosted deployment-chain evidence.

## Verification

- Pre-change `bin/test-fast` passed on 2026-05-10.
- Focused `bash -lc 'source bin/common.sh; run_mcp_consumer_package_smoke'`
  passed on 2026-05-10.
- Post-change `bin/test-fast` passed on 2026-05-10.
- Full local `bin/verify` passed on 2026-05-10.

## Decision Log

- 2026-05-10: The smoke now opens successful secure Streamable HTTP MCP
  sessions with `McpStreamableHttpClient.withAuthGrant`. Raw bearer clients
  remain in the generated smoke only for intentionally rejected bearer-token
  checks and cross-principal session reuse isolation.

## Handoff

Implementation and full local verification are complete. Push and hosted
deployment-chain evidence remain pending.

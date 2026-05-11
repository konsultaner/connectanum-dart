# Exec Plan: MCP Consumer Secure Session-Method Missing-Bearer Smoke

Status: complete locally; push and hosted evidence pending
Owner: Codex
Created: 2026-05-11
Last updated: 2026-05-11

## Goal

Make the generated router-hosted MCP consumer package smoke prove that
bearer-protected Streamable HTTP session methods reject missing credentials even
when a caller knows an active secure MCP session id.

## Scope

- In scope: bearerless secure-route Streamable HTTP GET/SSE poll rejection with
  an active session id and cursor copied from an authenticated session.
- In scope: bearerless secure-route Streamable HTTP DELETE session rejection with
  an active session id and cursor copied from an authenticated session.
- In scope: checks that rejected bearerless clients clear their local
  Streamable session state and that the authenticated owner session remains
  usable afterward.
- Out of scope: auth policy changes, token grant behavior changes, and
  documentation-only cleanup.

## Files Expected To Change

- `bin/common.sh`
- `docs/project_state.md`
- `docs/exec-plans/2026-05-11-mcp-consumer-secure-session-method-missing-bearer-smoke.md`
- Existing docs-only hosted-evidence updates from the previous MCP missing-bearer
  slice will remain bundled with this implementation commit.

## Preconditions

- Serena project onboarding is complete for this repository.
- The latest pushed branch checkpoint `e31f063` has clean hosted CI and
  deployment-chain evidence; remaining strict-audit gaps are operator-side
  release-hardening items.
- Pre-change `bin/test-fast` passed on 2026-05-11.

## Plan

1. Extend the generated consumer Streamable session-reuse isolation smoke with
   bearerless secure-route GET/SSE poll and DELETE session attempts using the
   primary authenticated session id.
2. Assert both rejected requests return HTTP 401, clear only the rejected
   client's Streamable session state, and leave the authenticated owner session
   usable.
3. Run focused generated smoke, `bin/test-fast`, and `bin/verify`; then push and
   collect hosted deployment-chain evidence.

## Verification

- Pre-change `bin/test-fast` passed on 2026-05-11.
- Focused `bash -n bin/common.sh` passed on 2026-05-11.
- Focused `bash -lc 'source bin/common.sh; run_mcp_consumer_package_smoke'`
  passed on 2026-05-11.
- Post-change `bin/test-fast` passed on 2026-05-11.
- Full local `bin/verify` passed on 2026-05-11.

## Decision Log

- 2026-05-11: Continue MCP downstream-readiness hardening on the neutral
  generated consumer package smoke. Existing reuse-isolation coverage proves
  other-principal bearer and public-route session reuse are rejected; the secure
  route also needs no-bearer GET/DELETE proof for known active session ids.

## Handoff

- Implementation and local verification are complete. Push, hosted CI, hosted
  log scan, and deployment-chain evidence still need to be collected.

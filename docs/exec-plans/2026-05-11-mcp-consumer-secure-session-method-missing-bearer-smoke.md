# Exec Plan: MCP Consumer Secure Session-Method Missing-Bearer Smoke

Status: complete; hosted CI and deployment-chain evidence clean
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
- Commit `d2c8e19` (`test: cover secure mcp session method auth`) is pushed
  to both remotes.
- GitHub `CI` run `25674548625` completed successfully for `d2c8e19` with
  `Fast Checks` and `Full Verify` green.
- The hosted CI log scan was clean.
- GitHub `Dart Package Publish Dry Run` run `25635686773` remains clean and
  relevant because no publish-sensitive package inputs changed after
  `90a27ca`.
- The deployment-chain audit passed with clean latest CI, clean hosted CI logs,
  and a clean relevant Dart package publish dry-run.
- The strict audit still reports only known operator-side release-hardening
  gaps: branch protection/required checks are absent,
  `.github/workflows/router-image.yml` is not yet visible from the default
  branch through the Actions API, and `ghcr.io/konsultaner/connectanum-router`
  is not visible in GitHub Packages.

## Decision Log

- 2026-05-11: Continue MCP downstream-readiness hardening on the neutral
  generated consumer package smoke. Existing reuse-isolation coverage proves
  other-principal bearer and public-route session reuse are rejected; the secure
  route also needs no-bearer GET/DELETE proof for known active session ids.

## Handoff

Implementation plus focused, fast, full local, and hosted verification are
complete. Remaining gaps are operator-side deployment-chain hardening:
branch protection/required checks, default-branch visibility for
`.github/workflows/router-image.yml`, and public visibility for
`ghcr.io/konsultaner/connectanum-router`.

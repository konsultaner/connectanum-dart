# Exec Plan: MCP Consumer Secure Unknown-Bearer WAMP Meta Pub/Sub Smoke

Status: complete locally; push and hosted evidence pending
Owner: Codex
Created: 2026-05-11
Last updated: 2026-05-11

## Goal

Make the generated router-hosted MCP consumer package smoke prove that secure
MCP endpoints reject an unknown raw bearer token on fresh clients across the
same direct JSON and Streamable WAMP meta/pub/sub route matrix used for
missing-bearer and stale/revoked-bearer checks.

## Scope

- In scope: an access token string that was never issued by the HTTP auth
  bridge, used by a fresh MCP client without an active Streamable session.
- In scope: direct JSON `connectanum.tools.list`, `connectanum.api.list`, and
  `connectanum.pubsub.subscribe` rejection coverage.
- In scope: direct JSON batches covering tool catalog and WAMP meta/pub/sub
  requests.
- In scope: Streamable HTTP `initialize`, batch `tools/list`, and batch
  WAMP meta/pub/sub `tools/call` rejection coverage.
- Out of scope: auth policy changes, token grant behavior changes, and
  documentation-only cleanup.

## Files Expected To Change

- `bin/common.sh`
- `docs/project_state.md`
- `docs/exec-plans/2026-05-11-mcp-consumer-secure-unknown-bearer-wamp-meta-pubsub-smoke.md`
- Existing docs-only hosted-evidence updates from the previous rejected-bearer
  WAMP meta/pub-sub slice remain bundled with this implementation commit.

## Preconditions

- Serena project onboarding is complete for this repository.
- The latest pushed branch checkpoint `66225d8` has clean hosted CI and
  deployment-chain evidence; remaining strict-audit gaps are operator-side
  release-hardening items.
- Pre-change `bin/test-fast` passed on 2026-05-11.

## Plan

1. Add a deterministic unknown bearer token value to the generated consumer
   smoke.
2. Reuse the existing fresh-client rejected-bearer helper before issuing any
   valid grant so unknown bearer credentials cover the direct JSON, WAMP
   meta/pub/sub, and Streamable HTTP route shapes.
3. Run focused generated smoke, `bin/test-fast`, and `bin/verify`; then push
   and collect hosted deployment-chain evidence.

## Verification

- Pre-change `bin/test-fast` passed on 2026-05-11.
- Focused `bash -n bin/common.sh` passed on 2026-05-11.
- Focused
  `bash -lc 'source bin/common.sh; run_mcp_consumer_package_smoke'` passed on
  2026-05-11.
- Post-change `bin/test-fast` passed on 2026-05-11.
- Full local `bin/verify` passed on 2026-05-11.

## Decision Log

- 2026-05-11: Continue MCP downstream-readiness hardening on the neutral
  generated consumer package smoke. Previous slices covered missing credentials
  and stale/revoked issued credentials; an unknown raw bearer token exercises
  the auth-present but invalid credential path before any consumer application
  needs private assumptions.

## Handoff

Implementation and local verification are complete. Push, hosted CI, hosted log
scan, and deployment-chain evidence still need to be collected.

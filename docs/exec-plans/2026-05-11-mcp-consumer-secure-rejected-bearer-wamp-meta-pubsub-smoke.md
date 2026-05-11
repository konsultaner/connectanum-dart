# Exec Plan: MCP Consumer Secure Rejected-Bearer WAMP Meta Pub/Sub Smoke

Status: complete locally; push and hosted evidence pending
Owner: Codex
Created: 2026-05-11
Last updated: 2026-05-11

## Goal

Make the generated router-hosted MCP consumer package smoke prove that secure
MCP endpoints reject stale or revoked bearer tokens on fresh clients across the
same direct JSON and Streamable WAMP meta/pub/sub route matrix used for
missing-bearer checks.

## Scope

- In scope: rotated or revoked bearer tokens used by a fresh MCP client without
  an active Streamable session.
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
- `docs/exec-plans/2026-05-11-mcp-consumer-secure-rejected-bearer-wamp-meta-pubsub-smoke.md`
- Existing docs-only hosted-evidence updates from the previous active-bearer
  WAMP meta/pub-sub slice remain bundled with this implementation commit.

## Preconditions

- Serena project onboarding is complete for this repository.
- The latest pushed branch checkpoint `9895c92` has clean hosted CI and
  deployment-chain evidence; remaining strict-audit gaps are operator-side
  release-hardening items.
- Pre-change `bin/test-fast` passed on 2026-05-11.

## Plan

1. Factor the secure MCP no-credentials route matrix into a reusable helper.
2. Reuse that helper for stale/revoked bearer token checks so fresh rejected
   bearer clients cover direct JSON, WAMP meta/pub/sub, and Streamable HTTP
   route shapes.
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
  generated consumer package smoke. The previous slice covered stale/revoked
  bearer tokens on already-active Streamable sessions; fresh rejected-bearer
  clients should hit the same app-facing WAMP meta/pub-sub route matrix before
  any private application assumptions are needed.

## Handoff

Implementation and local verification are complete. Push, hosted CI, hosted log
scan, and deployment-chain evidence still need to be collected.

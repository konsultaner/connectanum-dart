# Exec Plan: MCP Consumer Secure Active-Bearer WAMP Meta Pub/Sub Smoke

Status: complete locally; push and hosted evidence pending
Owner: Codex
Created: 2026-05-11
Last updated: 2026-05-11

## Goal

Make the generated router-hosted MCP consumer package smoke prove that secure
MCP endpoints reject stale or revoked bearer tokens on active Streamable
sessions for WAMP meta API and pub/sub calls, not only tool catalog calls.

## Scope

- In scope: active secure Streamable sessions whose bearer token has been
  rotated or revoked.
- In scope: direct JSON `connectanum.pubsub.subscribe` rejected-bearer coverage
  that preserves the consumer client's active Streamable session state.
- In scope: direct JSON batches mixing WAMP meta and pub/sub rejected-bearer
  coverage that preserves the active Streamable session state.
- In scope: Streamable HTTP batches that call WAMP meta and pub/sub tools
  through `tools/call` and clear the rejected caller's Streamable session state.
- Out of scope: auth policy changes, token grant behavior changes, and
  documentation-only cleanup.

## Files Expected To Change

- `bin/common.sh`
- `docs/project_state.md`
- `docs/exec-plans/2026-05-11-mcp-consumer-secure-active-bearer-wamp-meta-pubsub-smoke.md`
- Existing docs-only hosted-evidence updates from the previous MCP
  WAMP meta/pub-sub missing-bearer slice will remain bundled with this
  implementation commit.

## Preconditions

- Serena project onboarding is complete for this repository.
- The latest pushed branch checkpoint `3ca481c` has clean hosted CI and
  deployment-chain evidence; remaining strict-audit gaps are operator-side
  release-hardening items.
- Pre-change `bin/test-fast` passed on 2026-05-11.

## Plan

1. Expand the active rejected-bearer smoke helper with direct JSON WAMP pub/sub
   and mixed WAMP meta/pub/sub batch calls.
2. Add Streamable HTTP batch coverage for WAMP meta/pub/sub `tools/call`
   requests with stale or revoked bearer tokens.
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
  generated consumer package smoke. Secure missing-bearer coverage already
  proves WAMP meta/pub-sub access is gated before dispatch; active
  rejected-bearer coverage should pin the same app-facing WAMP paths for stale
  and revoked token lifecycles.

## Handoff

Implementation and local verification are complete. Push, hosted CI, hosted log
scan, and deployment-chain evidence still need to be collected.

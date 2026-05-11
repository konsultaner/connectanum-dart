# Exec Plan: MCP Consumer Secure Other-Principal Reuse WAMP Meta Pub/Sub Smoke

Status: complete locally; hosted CI and deployment-chain evidence pending
Owner: Codex
Created: 2026-05-11
Last updated: 2026-05-11

## Goal

Make the generated router-hosted MCP consumer package smoke prove that a bearer
token validly issued to one principal cannot reuse another client's active
secure Streamable HTTP session ID across the broad Streamable HTTP method
matrix that a downstream application would exercise.

## Scope

- In scope: a valid HTTP auth bridge bearer grant issued to a different
  principal from the primary Streamable MCP session owner.
- In scope: a secure `McpStreamableHttpClient` seeded with the primary owner's
  active `Mcp-Session-Id` and last event id.
- In scope: Streamable HTTP batches for tool/resource catalog methods and WAMP
  meta/pub/sub `tools/call` methods, notification requests, typed tools,
  typed resources, typed prompts, GET/SSE poll, and session delete.
- In scope: proving the primary owner Streamable MCP session remains usable
  after the rejected cross-principal reuse attempts.
- Out of scope: auth grant semantics, bearer validation policy changes, and
  consumer application assumptions.

## Files Expected To Change

- `bin/common.sh`
- `docs/project_state.md`
- `docs/exec-plans/2026-05-11-mcp-consumer-secure-other-principal-reuse-wamp-meta-pubsub-smoke.md`
- Existing docs-only hosted-evidence updates from the previous active
  unknown-bearer slice remain bundled with this implementation commit.

## Preconditions

- Serena project onboarding is complete for this repository.
- The latest pushed branch checkpoint `251e5e2` has clean hosted CI and
  deployment-chain evidence; remaining strict-audit gaps are operator-side
  release-hardening items.
- Pre-change `bin/test-fast` passed on 2026-05-11.

## Plan

1. Replace the single cross-principal `tools/list` session-reuse check in the
   generated consumer package smoke with a reusable Streamable method matrix.
2. Re-seed the reused session id and last event id before each rejected request
   because the client clears stale Streamable session state after failed
   session reuse attempts.
3. Cover Streamable batches, WAMP meta/pub/sub `tools/call` batches,
   notifications, tools, resources, prompts, poll, and delete.
4. Re-check the primary owner session after the rejected cross-principal
   attempts.
5. Run focused generated smoke, `bin/test-fast`, and `bin/verify`; then push
   and collect hosted deployment-chain evidence.

## Verification

- Pre-change `bin/test-fast` passed on 2026-05-11.
- Focused `bash -n bin/common.sh` passed on 2026-05-11.
- Focused
  `bash -lc 'source bin/common.sh; run_mcp_consumer_package_smoke'` passed on
  2026-05-11.
- Post-change `bin/test-fast` passed on 2026-05-11.
- Full local `bin/verify` passed on 2026-05-11.
- Hosted CI and deployment-chain evidence are pending until the implementation
  commit is pushed.

## Decision Log

- 2026-05-11: Continue MCP downstream-readiness hardening on the neutral
  generated consumer package smoke. Earlier slices covered fresh unknown
  bearer tokens, stale issued bearer tokens, and unknown bearer tokens on an
  active session id; valid credentials for the wrong principal on an active
  session id are the next auth/session correctness gap.

## Handoff

Implementation is locally complete and ready to push after bundling with the
project-state update. Hosted CI and deployment-chain evidence still need to be
collected after the commit lands on the branch.

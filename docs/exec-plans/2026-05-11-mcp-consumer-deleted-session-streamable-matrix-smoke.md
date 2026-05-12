# Exec Plan: MCP Consumer Deleted Session Streamable Matrix Smoke

Status: complete locally; hosted CI and deployment-chain evidence pending
Owner: Codex
Created: 2026-05-11
Last updated: 2026-05-12

## Goal

Make the generated router-hosted MCP consumer package smoke prove that a
client's deleted Streamable HTTP session cannot be reused across the broad
Streamable HTTP method matrix that a downstream application would exercise.

## Scope

- In scope: a neutral generated consumer package smoke client after successful
  Streamable initialization, GET/SSE polling, Last-Event-ID resume, and
  session deletion.
- In scope: reusing the deleted `Mcp-Session-Id` and last event id across
  Streamable batches, WAMP meta/pub/sub `tools/call` batches, notifications,
  typed tools, typed resources, typed prompts, GET/SSE poll, and session
  delete.
- In scope: proving each deleted-session reuse attempt returns HTTP 404 and
  clears local Streamable session state before the client can reinitialize.
- Out of scope: changing router auth policy, changing grant issuance, or
  adding consumer application assumptions.

## Files Expected To Change

- `bin/common.sh`
- `docs/project_state.md`
- `docs/exec-plans/2026-05-11-mcp-consumer-deleted-session-streamable-matrix-smoke.md`
- Existing docs-only hosted-evidence updates from the previous public-route
  slice remain bundled with this implementation commit.

## Preconditions

- Serena project onboarding is complete for this repository.
- The latest pushed branch checkpoint `ffa38c4` has clean hosted CI and
  deployment-chain evidence; remaining strict-audit gaps are operator-side
  release-hardening items.
- Pre-change `bin/test-fast` passed on 2026-05-11.

## Plan

1. Replace the generated consumer smoke's single deleted-session `tools/list`
   check with the reusable stale-session Streamable method matrix.
2. Re-seed the deleted session id and last event id before each rejected
   request because the client clears stale Streamable session state after
   session failures.
3. Cover Streamable batches, WAMP meta/pub/sub `tools/call` batches,
   notifications, tools, resources, prompts, poll, and delete.
4. Reinitialize the same client after the rejected deleted-session matrix to
   prove recovery remains usable.
5. Run focused generated smoke, `bin/test-fast`, and `bin/verify`; then push
   and collect hosted deployment-chain evidence.

## Verification

- Pre-change `bin/test-fast` passed on 2026-05-11.
- Focused `bash -n bin/common.sh` passed on 2026-05-12.
- Focused
  `bash -lc 'source bin/common.sh; run_mcp_consumer_package_smoke'` passed on
  2026-05-12.
- Post-change `bin/test-fast` passed on 2026-05-12.
- Full local `bin/verify` passed on 2026-05-12.
- Hosted CI and deployment-chain evidence are pending until the implementation
  commit is pushed.

## Decision Log

- 2026-05-11: Continue MCP downstream-readiness hardening on the neutral
  generated consumer package smoke. Earlier slices covered active session reuse
  from other principals, missing/invalid bearers, and public routes across the
  broad Streamable method matrix; the deleted-session lifecycle path still
  checked only `tools/list` after deletion and should exercise the same
  downstream-facing route surface.

## Handoff

Implementation is locally complete and ready to push after bundling with the
project-state update. Hosted CI and deployment-chain evidence still need to be
collected after the commit lands on the branch.

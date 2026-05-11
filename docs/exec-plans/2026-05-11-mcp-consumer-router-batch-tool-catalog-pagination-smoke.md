# Exec Plan: MCP Consumer Router Batch Tool Catalog Pagination Smoke

Status: complete locally; hosted evidence pending
Owner: Codex
Created: 2026-05-11
Last updated: 2026-05-11

## Goal

Make the generated router-hosted MCP consumer package smoke prove that batched
direct JSON and Streamable HTTP JSON-RPC clients can follow opaque tool catalog
cursors on real router-provided MCP endpoints.

## Scope

- In scope: direct JSON batch `connectanum.tools.list` cursor-head assertions
  plus follow-up cursor-page batches in `run_mcp_consumer_package_smoke`.
- In scope: Streamable HTTP batch `tools/list` cursor-head assertions plus
  follow-up cursor-page batches while preserving session and SSE event progress
  checks.
- In scope: the Streamable batch error-isolation path, so cursor traversal stays
  proven when one request in the batch fails.
- Out of scope: public API changes, router runtime pagination changes, and
  documentation-only cleanup.

## Files Expected To Change

- `bin/common.sh`
- `docs/project_state.md`
- `docs/exec-plans/2026-05-11-mcp-consumer-router-batch-tool-catalog-pagination-smoke.md`
- Existing docs-only hosted-evidence updates from the previous MCP catalog
  slice will remain bundled with this implementation commit.

## Preconditions

- Serena project onboarding is complete for this repository.
- The latest pushed branch checkpoint `9bfa925` has clean hosted CI and
  deployment-chain evidence; remaining strict-audit gaps are operator-side
  release-hardening items.
- Pre-change `bin/test-fast` passed on 2026-05-11.

## Plan

1. Add generated smoke helpers that validate a batched tool catalog head response
   and follow cursor-page responses through JSON-RPC batches.
2. Add direct JSON batch `connectanum.tools.list` coverage and prove it preserves
   direct JSON lifecycle isolation.
3. Replace first-page-only Streamable HTTP batch `tools/list` checks with cursor
   traversal assertions and keep SSE progress validation after each batch.
4. Run focused generated smoke, `bin/test-fast`, and `bin/verify`; then push and
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
  router-hosted consumer package smoke. Resource/template/prompt batch catalogs
  already follow cursors; batch tool catalogs still need the same direct JSON
  and Streamable HTTP proof for consumer applications and agents that issue
  JSON-RPC batches.

## Handoff

Local implementation and verification are complete. Hosted CI and
deployment-chain evidence will be recorded after the implementation commit is
pushed.

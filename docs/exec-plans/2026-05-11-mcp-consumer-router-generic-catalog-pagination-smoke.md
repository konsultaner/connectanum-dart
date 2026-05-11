# Exec Plan: MCP Consumer Router Generic Catalog Pagination Smoke

Status: active; full local verification complete
Owner: Codex
Created: 2026-05-11
Last updated: 2026-05-11

## Goal

Make the generated router-hosted MCP consumer package smoke prove that generic
JSON-RPC clients can follow opaque resource, resource-template, and prompt
catalog cursors on real router-provided MCP endpoints.

## Scope

- In scope: generic direct JSON `resources/list`,
  `resources/templates/list`, and `prompts/list` cursor-following assertions in
  `run_mcp_consumer_package_smoke`.
- In scope: generic Streamable HTTP JSON-RPC cursor-following assertions for
  the same catalogs while preserving session/event progress checks.
- Out of scope: public API changes, router runtime pagination changes, and
  documentation-only cleanup.

## Files Expected To Change

- `bin/common.sh`
- `docs/project_state.md`
- `docs/exec-plans/2026-05-11-mcp-consumer-router-generic-catalog-pagination-smoke.md`
- Existing docs-only hosted-evidence updates from the previous MCP catalog
  slice will remain bundled with the next implementation commit.

## Preconditions

- Serena project onboarding is complete for this repository.
- No active exec plan existed at session start.
- The latest pushed branch checkpoint `44e5fbc` has clean hosted CI and
  deployment-chain evidence; remaining strict-audit gaps are operator-side
  release-hardening items.
- Pre-change `bin/test-fast` passed on 2026-05-11.

## Plan

1. Add generated smoke helpers for generic JSON-RPC catalog cursor traversal.
2. Replace first-page-only generic direct JSON resource/template/prompt checks
   with cursor-following assertions.
3. Replace first-page-only generic Streamable HTTP resource/template/prompt
   checks with cursor-following assertions and keep SSE progress validation.
4. Run focused generated smoke, `bin/test-fast`, and `bin/verify`; then push
   and collect hosted deployment-chain evidence.

## Verification

- Pre-change `bin/test-fast` passed on 2026-05-11.
- Focused `bash -n bin/common.sh` passed on 2026-05-11.
- Focused `bash -lc 'source bin/common.sh; run_mcp_consumer_package_smoke'`
  passed on 2026-05-11.
- Post-change `bin/test-fast` passed on 2026-05-11.
- Full local `bin/verify` passed on 2026-05-11.
- Push and hosted deployment-chain evidence remain pending.

## Decision Log

- 2026-05-11: Continue MCP downstream-readiness hardening on the neutral
  router-hosted consumer package smoke. Typed helper catalogs and tool catalogs
  already follow cursors; generic JSON-RPC resource/template/prompt catalogs
  still need the same proof for consumer applications and agents that do not
  use typed helper methods.

## Handoff

Implementation plus focused, fast, and full local verification are complete.
Push and hosted deployment-chain evidence remain pending.

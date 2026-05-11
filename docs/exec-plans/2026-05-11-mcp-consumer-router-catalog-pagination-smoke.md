# Exec Plan: MCP Consumer Router Catalog Pagination Smoke

Status: active; full local verification complete
Owner: Codex
Created: 2026-05-11
Last updated: 2026-05-11

## Goal

Make the generated router-hosted MCP consumer package smoke prove that
downstream applications can follow opaque MCP catalog cursors against the real
router-provided MCP endpoint, not only against a fake client-only endpoint.

## Scope

- In scope: `bin/common.sh` generated consumer package smoke route catalogs and
  cursor-following assertions for resources, resource templates, and prompts
  over Streamable HTTP and lifecycle-free direct JSON helpers.
- Out of scope: public API changes, router runtime pagination changes, and
  speculative benchmark work.

## Files Expected To Change

- `bin/common.sh`
- `docs/project_state.md`
- `docs/exec-plans/2026-05-10-mcp-client-package-catalog-pagination-smoke.md`
- `docs/exec-plans/2026-05-11-mcp-consumer-router-catalog-pagination-smoke.md`

## Preconditions

- Serena project onboarding is complete for this repository.
- Pre-change `bin/verify` passed on 2026-05-11 before starting this slice.

## Plan

1. Add deterministic second-page resource, resource-template, and prompt
   entries to the generated router-hosted MCP route config.
2. Set the generated route catalog page sizes low enough to force opaque
   cursors while keeping the existing first-page expected entries stable.
3. Extend the generated consumer app to follow those cursors through public
   typed helpers over Streamable HTTP and direct JSON.
4. Run the focused generated smoke, `bin/test-fast`, and `bin/verify`; then
   push and collect hosted deployment-chain evidence.

## Verification

- Pre-change full local `bin/verify` passed on 2026-05-11.
- Focused `bash -n bin/common.sh` passed on 2026-05-11.
- Focused `bash -lc 'source bin/common.sh; run_mcp_consumer_package_smoke'`
  passed on 2026-05-11.
- Post-change `bin/test-fast` passed on 2026-05-11.
- Full local `bin/verify` passed on 2026-05-11.
- Push and hosted deployment-chain evidence remain pending.

## Decision Log

- 2026-05-11: Continue MCP downstream-readiness hardening on the real
  router-hosted consumer smoke because the previous slice proved cursor
  following only against a fake client-only endpoint.

## Handoff

Implementation plus focused, fast, and full local verification are complete.
Push and hosted deployment-chain evidence remain pending.

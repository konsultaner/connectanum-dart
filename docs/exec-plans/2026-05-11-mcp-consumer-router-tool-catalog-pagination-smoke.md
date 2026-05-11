# Exec Plan: MCP Consumer Router Tool Catalog Pagination Smoke

Status: active; full local verification complete
Owner: Codex
Created: 2026-05-11
Last updated: 2026-05-11

## Goal

Make the generated router-hosted MCP consumer package smoke prove that
downstream applications can follow opaque tool catalog cursors on real
router-provided MCP endpoints, including both initialized Streamable HTTP
`tools/list` and lifecycle-free direct JSON `connectanum.tools.list`.

## Scope

- In scope: `bin/common.sh` generated consumer package smoke route tool
  catalog page sizes and cursor-following assertions for public and
  bearer-protected MCP routes.
- In scope: keeping existing direct JSON lifecycle guarantees and Streamable
  session recovery checks valid when the expected procedure is no longer on
  the first tool catalog page.
- Out of scope: public API changes, router runtime pagination changes, and
  speculative benchmark work.

## Files Expected To Change

- `bin/common.sh`
- `docs/project_state.md`
- `docs/exec-plans/2026-05-11-mcp-consumer-router-catalog-pagination-smoke.md`
- `docs/exec-plans/2026-05-11-mcp-consumer-router-tool-catalog-pagination-smoke.md`

## Preconditions

- Serena project onboarding is complete for this repository.
- Pre-change `bin/test-fast` passed on 2026-05-11 before starting this slice.
- The previous router-hosted resource/template/prompt catalog pagination slice
  is complete through hosted CI and deployment-chain evidence.

## Plan

1. Force the generated public and bearer-protected router-hosted MCP tool
   catalogs to paginate with an opaque cursor.
2. Replace first-page-only tool catalog checks with a generated helper that
   follows every cursor, asserts deterministic sorted/unique names, and proves
   the registered consumer procedure plus Connectanum meta/pubsub tools remain
   discoverable.
3. Exercise the helper through both Streamable `tools/list` and lifecycle-free
   direct JSON `connectanum.tools.list` paths, including after active
   Streamable initialization and error recovery.
4. Run focused generated smoke, `bin/test-fast`, and `bin/verify`; then push
   and collect hosted deployment-chain evidence.

## Verification

- Pre-change `bin/test-fast` passed on 2026-05-11.
- Focused `bash -n bin/common.sh` passed on 2026-05-11.
- Focused `bash -lc 'source bin/common.sh; run_mcp_consumer_package_smoke'`
  initially exposed a remaining first-page-only generic direct JSON
  `connectanum.tools.list` assertion; after the cursor-following fix, the
  focused smoke passed on 2026-05-11.
- Post-change `bin/test-fast` passed on 2026-05-11.
- Full local `bin/verify` passed on 2026-05-11.
- Push and hosted deployment-chain evidence remain pending.

## Decision Log

- 2026-05-11: Continue MCP downstream-readiness hardening on the real
  router-hosted consumer smoke because the previous slice proved pagination for
  resource/template/prompt catalogs, while tool/meta discovery still assumed
  the expected procedure appeared on the first page.

## Handoff

Implementation plus focused, fast, and full local verification are complete.
Push and hosted deployment-chain evidence remain pending.

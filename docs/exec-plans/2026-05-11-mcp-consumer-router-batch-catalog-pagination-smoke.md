# Exec Plan: MCP Consumer Router Batch Catalog Pagination Smoke

Status: complete; hosted CI and deployment-chain evidence clean
Owner: Codex
Created: 2026-05-11
Last updated: 2026-05-11

## Goal

Make the generated router-hosted MCP consumer package smoke prove that batched
direct JSON and Streamable HTTP JSON-RPC clients can follow opaque resource,
resource-template, and prompt catalog cursors on real router-provided MCP
endpoints.

## Scope

- In scope: direct JSON batch `resources/list`,
  `resources/templates/list`, and `prompts/list` cursor-head assertions plus a
  follow-up cursor-page batch in `run_mcp_consumer_package_smoke`.
- In scope: Streamable HTTP batch cursor-head assertions and cursor-page batch
  coverage for the same catalogs while preserving session and SSE event
  progress checks.
- Out of scope: public API changes, router runtime pagination changes, and
  documentation-only cleanup.

## Files Expected To Change

- `bin/common.sh`
- `docs/project_state.md`
- `docs/exec-plans/2026-05-11-mcp-consumer-router-batch-catalog-pagination-smoke.md`
- Existing docs-only hosted-evidence updates from the previous MCP catalog
  slice will remain bundled with this implementation commit.

## Preconditions

- Serena project onboarding is complete for this repository.
- No active exec plan existed at session start.
- The latest pushed branch checkpoint `0601652` has clean hosted CI and
  deployment-chain evidence; remaining strict-audit gaps are operator-side
  release-hardening items.
- Pre-change `bin/test-fast` passed on 2026-05-11.

## Plan

1. Add generated smoke helpers that validate a paginated catalog head response
   and a cursor-page response from batch JSON-RPC results.
2. Replace first-page-only direct JSON batch resource/template/prompt catalog
   checks with cursor-head and cursor-page batch assertions.
3. Replace first-page-only Streamable HTTP batch catalog checks with the same
   cursor traversal assertions and keep SSE progress validation after each
   batch.
4. Run focused generated smoke, `bin/test-fast`, and `bin/verify`; then push
   and collect hosted deployment-chain evidence.

## Verification

- Pre-change `bin/test-fast` passed on 2026-05-11.
- Focused `bash -n bin/common.sh` passed on 2026-05-11.
- Focused `bash -lc 'source bin/common.sh; run_mcp_consumer_package_smoke'`
  passed on 2026-05-11.
- Post-change `bin/test-fast` passed on 2026-05-11.
- Full local `bin/verify` passed on 2026-05-11.
- Commit `9bfa925` (`test: page router mcp batch catalogs`) is pushed to both
  remotes.
- GitHub `CI` run `25667401950` completed successfully for `9bfa925` with
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
  router-hosted consumer package smoke. Typed helper catalogs and generic
  single-request catalogs already follow cursors; batch resource/template/prompt
  catalog calls still need the same proof for consumer applications and agents
  that issue JSON-RPC batches.

## Handoff

Implementation plus focused, fast, full local, and hosted verification are
complete. Remaining gaps are operator-side deployment-chain hardening:
branch protection/required checks, default-branch visibility for
`.github/workflows/router-image.yml`, and public visibility for
`ghcr.io/konsultaner/connectanum-router`.

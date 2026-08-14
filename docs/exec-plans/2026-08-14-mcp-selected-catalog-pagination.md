# Exec Plan: MCP Selected Catalog Pagination

Status: active
Owner: Codex
Created: 2026-08-14
Last updated: 2026-08-14

## Goal

Let the shipped router-hosted MCP client select configured resources and
prompts from any advertised catalog page, then prove the behavior through
direct JSON and compatibility Streamable HTTP against a neutral packaged
router endpoint.

## Scope

- In scope:
  - One bounded reusable exact-entry pagination helper for resource, prompt,
    and resource-template catalogs.
  - Cursor-aware typed and raw JSON-RPC resource/prompt selection in direct
    JSON, active-session direct JSON, and compatibility Streamable flows.
  - Batch-page validation that accepts a selected entry on a later advertised
    page without weakening response-shape or cursor checks.
  - A protected JSON-response Router Image fixture with the selected resource
    and prompt on page two, plus explicit package-client page-count evidence.
- Out of scope:
  - Automatically loading resources or prompts without caller selection.
  - Changing router catalog ordering, cursor encoding, or authorization.
  - New MCP methods or protocol-version behavior.

## Plan

1. Run the pre-change fast gate and add fail-first public-client and Router
   Image pagination contracts.
2. Implement reusable catalog traversal and apply it to every selected
   resource/prompt compatibility path.
3. Run focused contracts and local Router Image evidence, then complete
   `bin/test-fast`, `bin/verify`, privacy, and package validation.
4. Commit and push the implementation with project-state updates, then collect
   required exact-head hosted evidence and run the strict deployment audit.

## Verification

- `python3 -m unittest tool.test_mcp_consumer_package_boundary`
- `python3 -m unittest tool.test_router_image_mcp_smoke`
- `dart analyze packages/connectanum_mcp`
- `bash -n bin/router-image-mcp-smoke`
- `bin/router-image-mcp-smoke <local-image>` when a current image is available
- `bin/test-fast`
- `bin/verify`

## Decision Log

- 2026-08-14: Selected catalog entries must not be coupled to router page
  size or declaration order. The public executable will traverse opaque
  cursors with repeated-cursor detection and expose page counts as smoke
  evidence.
- 2026-08-14: Batch requests remain single-page protocol examples. Their
  validation must require a valid catalog page and either the selected entry
  or a continuation cursor; exact selection is proved by the typed and raw
  cursor-aware paths.

## Progress

- 2026-08-14: Pre-change and post-change `bin/test-fast` pass. The fail-first
  public-client and Router Image contracts reproduced the first-page
  assumptions before implementation; 51 focused Python contracts, package
  analysis, shell syntax, and diff checks pass after implementation.
- 2026-08-14: A fresh local Router Image built from the worktree passes the
  complete official SDK and isolated globally activated package-client smoke.
  Public and standard protected compatibility endpoints report one resource,
  prompt, and template page; the protected JSON-response endpoint reports two
  pages for every typed and raw direct/Streamable selection path. Its modern
  stateless flow also resolves the dynamic resource on page three.
- 2026-08-14: Full `bin/verify` passes with zero formatting changes. The matrix
  includes 114 Rust core, 52 Rust FFI, 364 Dart core, 108 MCP, 280 client/MCP,
  97 benchmark, 37 live WAMP workload, 441 router, six remote-auth, and 13
  native follow-up tests plus every maintained isolated consumer and the
  Chrome Dart2Wasm smoke.
- 2026-08-14: The clean implementation commit passes strict release-ready
  dry-runs for all seven synchronized `3.0.0-beta` package archives with zero
  warnings, no private workspace dependency blockers, and every declared
  executable present.

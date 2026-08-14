# Exec Plan: MCP Selected Tool Pagination

Status: active
Owner: Codex
Created: 2026-08-14
Last updated: 2026-08-14

## Goal

Let the shipped router-hosted MCP client select and invoke a tool from any
advertised catalog page, then prove typed, raw JSON-RPC, direct JSON, and
compatibility Streamable HTTP behavior against a neutral packaged router
endpoint.

## Scope

- In scope:
  - Reuse the bounded exact-entry catalog walker for standard and Connectanum
    tool catalogs.
  - Cursor-aware typed and raw JSON-RPC selected-tool discovery in direct JSON,
    active-session direct JSON, and compatibility Streamable flows.
  - Single-page batch validation that accepts a selected tool on a later
    advertised page without weakening catalog or cursor validation.
  - A protected JSON-response Router Image fixture with the selected WAMP tool
    after the first page, plus explicit package-client page-count evidence.
- Out of scope:
  - Automatically invoking tools without caller selection.
  - Changing router catalog ordering, cursor encoding, tool authorization, or
    header-parameter semantics.
  - New MCP methods or protocol-version behavior.

## Plan

1. Run the pre-change fast gate and add fail-first public-client and Router
   Image tool-pagination contracts.
2. Reuse the catalog walker for every selected-tool typed and raw catalog path,
   and make batch catalog checks continuation-aware.
3. Run focused contracts and a fresh local Router Image smoke, then complete
   `bin/test-fast`, `bin/verify`, privacy, and package validation.
4. Commit and push the implementation with project-state updates, collect
   required exact-head hosted evidence, and run the strict deployment audit.

## Verification

- `python3 -m unittest tool.test_mcp_consumer_package_boundary`
- `python3 -m unittest tool.test_router_image_mcp_smoke`
- `dart analyze packages/connectanum_mcp`
- `bash -n bin/router-image-mcp-smoke`
- `bin/router-image-mcp-smoke <local-image>`
- `bin/test-fast`
- `bin/verify`

## Decision Log

- 2026-08-14: Caller-selected tools are the remaining catalog-backed action
  coupled to router page size in the shipped executable. The same bounded,
  repeated-cursor-safe walker used for resources and prompts will own tool
  selection.
- 2026-08-14: Batch requests remain single-page protocol examples. Their
  catalog result is valid when it contains the selected tool or advertises a
  continuation cursor; typed and raw sequential paths prove exact selection.

## Progress

- 2026-08-14: Pre-change `bin/test-fast` passes the complete fast regression,
  package/consumer, live WAMP, and router CLI smoke matrix.
- 2026-08-14: Fail-first public-client and Router Image contracts reproduce
  the first-page-only selected-tool assumptions. The implementation now reuses
  the bounded cursor walker for standard, Connectanum, and raw JSON-RPC tool
  catalogs in direct JSON, active-session direct JSON, and compatibility
  Streamable flows. Single-page batch checks accept a valid continuation
  cursor while the sequential paths still require the exact selected tool.
- 2026-08-14: All 51 focused Python contracts, MCP package analysis, shell
  syntax, diff checks, the complete 108-test MCP package suite, and post-change
  `bin/test-fast` pass. Full `bin/verify` passes with zero formatting changes:
  114 Rust core, 52 Rust FFI, 364 Dart core, 108 MCP, 280 client/MCP, 97
  benchmark, 37 live WAMP workload, 441 router, six remote-auth, and 13 native
  follow-up tests plus every maintained isolated consumer and Chrome Dart2Wasm
  smoke.
- 2026-08-14: The neutral Router Image fixture selects
  `connectanum.api.list`; a one-entry protected JSON-response tool catalog
  places it on page two and requires page-count evidence from every typed and
  raw direct/Streamable discovery path. Local Docker image construction stalls
  before the first build step in both BuildKit and legacy-builder modes, so
  exact-head hosted Router Image evidence remains required after push.
- 2026-08-14: A pre-commit strict package dry-run reports zero warnings for
  the first five synchronized archives, then stops on the expected dirty-git
  warning for the modified `connectanum_mcp` archive. Clean-commit package
  validation and hosted deployment evidence remain.

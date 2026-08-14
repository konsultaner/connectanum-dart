# Exec Plan: MCP WAMP API Pagination

Status: active
Owner: Codex
Created: 2026-08-14
Last updated: 2026-08-14

## Goal

Bound router-provided `connectanum.api.list` responses and let the shipped Dart
client discover a caller-selected WAMP procedure or topic on any opaque cursor
page through direct JSON, active-session direct JSON, and compatibility
Streamable HTTP.

## Scope

- In scope:
  - Optional bounded pagination in `McpWampApi` with deterministic procedure
    then topic ordering, query/catalog-bound opaque cursors, and stale-cursor
    rejection.
  - Snake-case and camel-case router route options for the WAMP API page size.
  - Public typed WAMP API helpers that send validated cursors and validate
    returned continuation cursors.
  - Bounded selected procedure/topic traversal for typed and raw JSON-RPC
    direct, active-session direct, and compatibility Streamable paths.
  - Continuation-aware single-page batch checks and Router Image page-count
    evidence from a neutral protected JSON-response endpoint.
- Out of scope:
  - Changing default unpaged behavior when no WAMP API page size is configured.
  - Paginating standard WAMP Meta API procedure results.
  - Changing WAMP procedure/topic authorization, ordering, or pub/sub ownership.

## Plan

1. Complete the pre-change fast gate and add fail-first MCP core, public-client,
   router-option, package-boundary, and Router Image contracts.
2. Implement cursor pagination and reuse the bounded advertised-entry walker
   across every selected WAMP procedure/topic catalog path.
3. Run focused suites, package analysis, shell/privacy checks, `bin/test-fast`,
   and full `bin/verify`.
4. Commit and push the implementation with the pending hosted-evidence docs,
   then collect exact-head package, CI, Router Image, and strict-audit evidence.

## Verification

- `dart test packages/connectanum_mcp/test/wamp_api_test.dart -r expanded`
- `dart test packages/connectanum_client/test/mcp/streamable_http_client_test.dart -r expanded`
- `dart test packages/connectanum_router/test/router_json_test.dart -r expanded`
- `python3 -m unittest tool.test_mcp_consumer_package_boundary`
- `python3 -m unittest tool.test_router_image_mcp_smoke`
- `dart analyze packages/connectanum_mcp packages/connectanum_client packages/connectanum_router`
- `bash -n bin/router-image-mcp-smoke`
- `bin/test-fast`
- `bin/verify`

## Decision Log

- 2026-08-14: `connectanum.api.list` is the remaining router-provided catalog
  used by the public smoke that can return an unbounded response and whose
  caller-selected procedure/topic checks inspect only one result page.
- 2026-08-14: Pagination is opt-in at the server/router configuration boundary
  to preserve existing standalone API behavior. When both kinds are requested,
  one deterministic sequence contains procedures first and topics second.

## Handoff

- The implementation is complete. The optional page-size boundary, opaque
  query/catalog-bound cursors, router route aliases, public typed/direct cursor
  helpers, and bounded typed/raw selected-entry traversal are covered by the
  focused MCP, client, router, package-boundary, and Router Image contracts.
  Public and standard protected image routes retain one-page behavior while
  the protected JSON-response route reaches the selected procedure on page
  seven and the selected topic on page two.
- Pre-change and post-change `bin/test-fast` pass. Focused package analysis,
  shell syntax, Python compilation/contracts, native router integration, and
  `git diff --check` pass. Full `bin/verify` passes with zero formatting
  changes across Rust core/FFI, Dart package and native suites, generated and
  globally activated consumer smokes, live WAMP/benchmark coverage, the full
  router suite, Chrome, and Dart2Wasm.
- The implementation commit, maintained-remote pushes, exact-head CI/package/
  Router Image evidence, and strict deployment-chain audit remain.

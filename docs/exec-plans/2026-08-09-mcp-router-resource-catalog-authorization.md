# MCP Router Resource Catalog Authorization

Status: active; implementation and local verification are green, exact-head
hosted deployment evidence remains

## Goal

Make router-hosted MCP dynamic-resource discovery follow the route principal's
WAMP call authorization while preserving public static resources, direct JSON
sessionlessness, compatibility Streamable session state, and modern resource
list-change delivery.

## Context

Every router-hosted request refreshes the WAMP tool catalog and filters a live
procedure by the route principal's call permission. A configured dynamic
resource backed by that procedure remains in `resources/list`, however, even
when the procedure tool is hidden and `resources/read` will be denied. This
leaks protected resource metadata and makes resource discovery disagree with
execution authorization.

## Plan

1. Add a native-router fail-first regression that denies the configured read
   procedure and proves the resource is still visible through direct JSON.
2. Build the resource catalog from the same per-refresh authorization snapshot
   as WAMP procedure discovery, with one decision per action/URI.
3. Advertise and emit resource list-change notifications when a dynamic
   resource becomes visible or hidden, covering modern request-scoped listeners
   and compatibility Streamable session continuity.
4. Run focused analysis/tests, post-change `bin/test-fast`, and full
   `bin/verify`; publish both maintained remotes and audit hosted evidence if
   green.

## Progress

- 2026-08-09: Exact-head CI and the comprehensive deployment audit are green at
  `458d3059`; pre-change `bin/test-fast` passes all 360 core, 98 MCP, and 280
  MCP/client cases, all 96 benchmark tests including 36 live WAMP workloads,
  and the complete generated/global consumer plus Router CLI smoke matrix.
- 2026-08-09: A native-router fail-first regression proves a configured dynamic
  resource remains visible while its backing WAMP procedure is denied, and
  that denied direct JSON reads and subscription setup disclose the hidden
  resource before the implementation change.
- 2026-08-09: Catalog refresh now builds tool and dynamic-resource visibility
  from one route-principal authorization snapshot, reuses one future per
  action/URI, preserves static resources, and replaces registries only when
  their signatures change. Direct JSON reads remain sessionless, compatibility
  Streamable reads preserve session and cursor state, and hidden reads and new
  subscriptions return `resourceNotFound`.
- 2026-08-09: Dynamic-resource endpoints advertise resource list changes,
  modern listeners can request them, and catalog visibility transitions emit
  both modern and compatibility notifications. Router analysis and the new
  plus six adjacent native authorization/catalog/resource regressions pass.
- 2026-08-09: Post-change `bin/test-fast` passes all 360 core, 98 MCP, and 280
  MCP/client cases, all 96 benchmark tests including 36 live WAMP workloads,
  and the complete generated/global consumer plus Router CLI smoke matrix.
- 2026-08-09: Full `bin/verify` passes formatting; all 114 Rust core and 52
  Rust FFI tests plus focused metrics; 360 Dart core, 98 MCP, 280 MCP/client,
  96 benchmark, and 406 Router tests; the 6-case remote-auth and 13-case native
  follow-ups; every generated and globally activated consumer smoke; and
  Chrome/Dart2Wasm.

## Handoff

- Implementation and local verification are complete. Push both maintained
  `master` branches, run the Router Image dry run, require clean exact-head CI,
  package, WAMP, and image evidence, then run the comprehensive strict
  deployment-chain audit. Do not create or move an RC tag without explicit
  approval.

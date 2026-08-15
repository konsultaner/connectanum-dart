# Exec Plan: MCP Anonymous Route Scope-Key Isolation

Status: active
Owner: Codex
Created: 2026-08-15
Last updated: 2026-08-15

## Goal

Prevent distinct public router-hosted MCP routes from sharing an internal WAMP
session when configurable route paths, realm URIs, and session-profile names
form the same delimiter-joined cache key.

## Scope

- In scope:
  - prove isolation between two anonymous MCP routes whose route, realm, and
    profile tuples collide under the current colon-joined key;
  - replace the ambiguous tuple serialization with an opaque,
    collision-resistant scope digest;
  - prove modern direct tool discovery and calls stay sessionless and use only
    the route's configured WAMP realm.
- Out of scope:
  - restricting currently valid route paths, realm URIs, or profile names;
  - changing MCP authentication or authorization policy;
  - changing Streamable HTTP protocol-session ownership.

## Files Expected To Change

- `packages/connectanum_router/lib/src/router/router_instance/router_mcp.dart`
- `packages/connectanum_router/test/router_runtime_test.dart`
- `ROADMAP.md`
- `docs/project_state.md`
- this execution plan

## Preconditions

- No unrelated Codex process is editing this repository.
- Both maintained `master` branches point at commit `e444c989`; its exact-head
  deployment chain and comprehensive strict audit are green.
- Existing hosted-evidence notes are docs-only and will be bundled with this
  implementation.
- Pre-change `bin/test-fast` exits zero across the maintained repository,
  live-WAMP, executable, and consumer-smoke matrix.

## Plan

1. Add a public two-route MCP runtime regression with deliberately
   delimiter-colliding route/realm/profile tuples and realm-specific tools.
2. Encode the anonymous MCP route scope as an unambiguous opaque digest while
   retaining route-local internal-session reuse.
3. Run focused checks and `bin/verify`, update durable readiness state, publish
   the implementation to both maintained remotes, and inspect the exact-head
   GitHub deployment chain.

## Verification

- `bin/test-fast`
- Focused router runtime regression before and after implementation
- Existing protected and new anonymous delimiter-collision regressions
- HTTP-auth provider and router runtime matrix
- `dart analyze packages/connectanum_router`
- `bin/verify`
- Exact-head GitHub CI, package dry run, WAMP benchmark, Router Image dry run,
  and strict deployment-chain audit after publication

## Decision Log

- 2026-08-15: Anonymous MCP route cache keys included listener ID, route path,
  realm URI, and session-profile name, but joined the configurable strings with
  `:`. Distinct route scopes could therefore resolve to the same cache key.
- 2026-08-15: The fail-first public regression issued modern sessionless tool
  discovery through both colliding routes. The second route returned the first
  realm's tool catalog instead of its configured realm's catalog.
- 2026-08-15: The cache key now hashes a JSON-encoded tuple of listener, route,
  realm, and profile into a fixed opaque scope key. Both routes remain
  sessionless, expose only their own realm tools, and return realm-specific
  direct tool-call results.
- 2026-08-15: Router analysis, both delimiter-collision regressions, and the
  complete HTTP-auth provider plus router runtime matrix pass all 105 cases.
- 2026-08-15: Full `bin/verify` exits zero with formatting unchanged; Rust core
  and FFI green; 366 core tests; 116 MCP tests; the complete 293-case
  MCP/client suite; 97 benchmark tests including all 37 live WAMP workloads;
  the 445-case router suite; six remote-auth tests; 13 native follow-ups; every
  maintained consumer smoke; Chrome; and Dart2Wasm green.

## Handoff

- Implementation and local verification are complete; publication and
  exact-head hosted evidence remain.

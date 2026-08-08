# MCP Router Resource Subscribe Single Authorization

Status: active; implementation and local verification are green, hosted
evidence remains

## Goal

Make each router-hosted MCP dynamic-resource subscription owner perform one
subscribe authorization decision while keeping the shared physical WAMP
subscription reusable across compatibility Streamable sessions and modern
request-scoped listeners.

## Context

Compatibility `resources/subscribe` and modern `subscriptions/listen` already
authorize the configured resource update topic for each logical owner. When no
shared physical subscription exists, `_ensureResourceUpdateSubscription` then
delegates to the ordinary MCP WAMP subscribe callback, which authorizes the
same topic a second time. Dynamic authorization providers can therefore reject
or fail one logical operation only when it happens to create the physical
subscription, while later owners of an existing shared subscription see one
decision.

## Plan

1. Add native-router fail-first coverage for compatibility and modern resource
   subscription owners with a provider that fails a duplicate subscribe check.
2. Split already-authorized internal WAMP subscription creation from the
   explicit MCP WAMP subscribe operation without weakening per-owner checks.
3. Prove update delivery, Streamable session/cursor stability, modern
   sessionlessness, cleanup, and exact authorization-request counts.
4. Run focused analysis/tests, post-change `bin/test-fast`, and full
   `bin/verify`; publish both maintained remotes and audit hosted evidence if
   green.

## Progress

- 2026-08-08: Exact-head CI and the comprehensive deployment audit are green at
  `f808355f`; pre-change `bin/test-fast` passes.
- 2026-08-08: A native-router regression that arms a dynamic authorization
  provider to fail the second matching subscribe decision reproduces the
  compatibility `resources/subscribe` failure before the implementation
  change. The same coverage also exercises a modern request-scoped
  `subscriptions/listen` owner, exact decision counts, resource-update
  delivery, compatibility session stability, modern sessionlessness, and
  cleanup.
- 2026-08-08: `_ensureResourceUpdateSubscription` now creates its physical WAMP
  subscription through an already-authorized internal path. Explicit MCP WAMP
  subscribe operations retain their own authorization check and share the same
  queue, capacity, tracking, and cleanup implementation.
- 2026-08-08: Focused Router analysis and the new plus adjacent native tests
  pass. Post-change `bin/test-fast` and full `bin/verify` pass, including 114
  Rust core tests plus serializer integrations; 52 Rust FFI tests plus the
  focused metrics check; 360 Dart core, 98 MCP, 280 MCP/client, 96 benchmark,
  and 404 Router tests; the 6-case remote-auth and 13-case native follow-ups;
  every generated and globally activated consumer smoke; and Chrome/Dart2Wasm.

## Handoff

- Active. Commit, push both maintained remotes, and audit exact-head hosted
  evidence.

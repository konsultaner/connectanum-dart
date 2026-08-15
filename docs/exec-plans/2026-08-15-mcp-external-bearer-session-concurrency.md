# Exec Plan: MCP External Bearer Session Concurrency

Status: active; implementation and local verification green, publication pending
Owner: Codex
Created: 2026-08-15
Last updated: 2026-08-15

## Goal

Make configured external JWT, OIDC, and OAuth bearer authorization-context
replacement linearizable for router-hosted MCP consumers. Concurrent validated
results for one credential must not reuse an internal session while it is
closing or leave a newly initialized Streamable HTTP session bound to stale
authorization state.

## Scope

- In scope:
  - serialize external bearer session-context replacement per opaque credential;
  - retain concurrency between unrelated bearer credentials;
  - prove the race through public protected MCP Streamable HTTP requests backed
    by a controlled OAuth introspection service;
  - preserve fail-closed stale MCP session behavior and fresh-session recovery.
- Out of scope:
  - changing external provider validation or caching policy;
  - changing client-side grant refresh behavior;
  - adding new MCP methods or protocol-era behavior.

## Files Expected To Change

- `packages/connectanum_router/lib/src/router/router_instance/router_binding.dart`
- `packages/connectanum_router/test/router_runtime_test.dart`
- `ROADMAP.md`
- `docs/project_state.md`
- this execution plan

## Preconditions

- No unrelated Codex process is editing this repository.
- Both maintained `master` branches point at commit `27198209` and its exact-head
  deployment chain is green.
- Pre-change `bin/test-fast` exits zero across the maintained repository,
  real-router, executable, and isolated consumer-smoke matrix.

## Plan

1. Extend the existing OAuth-introspection MCP runtime regression with two
   concurrent validated role results that expose stale-session reuse.
2. Serialize external session-context replacement per credential and clean up
   the turn state deterministically.
3. Run focused tests and `bin/verify`, update durable readiness state, publish
   the implementation to both maintained remotes, and inspect the exact-head
   GitHub deployment chain.

## Verification

- `bin/test-fast`
- Focused router runtime regression before and after the implementation
- `dart analyze packages/connectanum_router`
- `bin/verify`
- Exact-head GitHub CI, package dry run, WAMP benchmark, Router Image dry run,
  and strict deployment-chain audit after publication

## Decision Log

- 2026-08-15: Use a binding-owned turn chain keyed by the existing opaque
  provider/realm/profile/credential fingerprint. This orders context
  replacement for one bearer without retaining the raw token or serializing
  unrelated credentials.
- 2026-08-15: Exercise the race at the public protected Streamable HTTP boundary
  with controlled introspection completion order rather than asserting private
  session maps.
- 2026-08-15: The fail-first regression returned HTTP 404 from the concurrently
  initialized member session because it reused the internal session being
  closed by the preceding blocked result. The per-credential turn chain makes
  the same regression pass and preserves the existing stale-session 404.
- 2026-08-15: Router analysis is clean, the focused race passes five consecutive
  runs, and the HTTP-auth provider plus router runtime matrix passes all 103
  cases.
- 2026-08-15: Full `bin/verify` exits zero with formatting unchanged; Rust core
  and FFI green; 366 core tests; 116 MCP tests; the complete 293-case MCP/client
  suite; 97 benchmark tests including all 37 live WAMP workloads; the 443-case
  router suite; six remote-auth tests; 13 native follow-ups; every maintained
  consumer smoke; Chrome; and Dart2Wasm green.

## Handoff

- Publication and hosted evidence remain pending.

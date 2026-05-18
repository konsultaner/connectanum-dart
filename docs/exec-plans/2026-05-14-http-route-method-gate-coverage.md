# Exec Plan: HTTP Route Method Gate Coverage

Status: complete
Owner: Codex
Created: 2026-05-14
Last updated: 2026-05-14

## Goal

Prove the HTTP bridge route method/protocol whitelist path is release-ready by
covering method mismatch rejection at both the native HTTP boundary and the
Dart synthetic runtime boundary.

## Scope

- In scope: method mismatch route-resolution coverage, native HTTP/1.1 405
  rejection before WAMP-backed dispatch, Dart runtime 405 rejection, roadmap and
  project-state evidence updates.
- Out of scope: new HTTP translation-table features, catch-all route syntax,
  release tag movement, and hosted release artifact publication.

## Files Expected To Change

- `native/transport/ct_core/src/config.rs`
- `native/transport/ct_core/src/lib.rs`
- `packages/connectanum_router/test/router_runtime_test.dart`
- `ROADMAP.md`
- `docs/project_state.md`

## Preconditions

- PR/tag release promotion remains operator-gated.
- Pre-edit `bin/test-fast` must pass before this slice changes code.

## Plan

1. Add native config coverage for allowed-method reporting and method
   normalization.
2. Add native HTTP listener coverage proving disallowed methods return 405 and
   do not enqueue a WAMP-backed HTTP request.
3. Add Dart runtime coverage proving synthetic HTTP route method mismatches
   return 405 with the `Allow` header and do not dispatch.
4. Run focused tests, then `bin/verify`, and record evidence.

## Verification

- `bin/test-fast` passed before edits on 2026-05-14.
- `cargo test --manifest-path native/transport/Cargo.toml -p ct_core http_route_method_mismatch` passed on 2026-05-14.
- `dart test packages/connectanum_router/test/router_runtime_test.dart --name "typed HTTP route method restrictions" --chain-stack-traces` passed on 2026-05-14.
- `bin/verify` passed on 2026-05-14.

## Decision Log

- 2026-05-14: Existing code already exposes typed route `methods` and
  `protocols`, and native/Dart paths already contain rejection branches. This
  slice adds missing method-mismatch evidence rather than widening MCP or
  speculative transport work.

## Handoff

- Complete. HTTP route method/protocol whitelist enforcement now has native
  and Dart runtime evidence, and the roadmap item is closed. Release promotion
  remains gated by PR review/tag approval rather than this slice.

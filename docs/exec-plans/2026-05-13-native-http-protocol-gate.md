# Exec Plan: native-http-protocol-gate

Status: complete
Owner: Codex
Created: 2026-05-13
Last updated: 2026-05-13

## Goal

Make real native HTTP route protocol mismatches behave like the Dart synthetic
router path: reject before WAMP/Dart dispatch with `426 Upgrade Required` and
allowed-protocol response metadata.

## Scope

- In scope: native route matching, HTTP/1.1/2/3 rejection responses, route
  protocol alias normalization, focused native tests, and project-state
  checkpointing.
- Out of scope: speculative HTTP transport tuning, new MCP helper variants, or
  public release publishing.

## Files Expected To Change

- `native/transport/ct_core/src/config.rs`
- `native/transport/ct_core/src/lib.rs`
- `docs/project_state.md`

## Preconditions

- `bin/test-fast` must pass before native routing changes.

## Plan

1. Add a native `ProtocolNotAllowed` route-match result that collects allowed
   protocols when path and method match but the negotiated HTTP protocol does
   not.
2. Return `426 Upgrade Required` from HTTP/1.1, HTTP/2, and HTTP/3 handlers,
   including `x-connectanum-allowed-protocols` and HTTP/1.1 `Upgrade` metadata
   where applicable.
3. Cover the route matcher and real HTTP/1.1 listener response path with
   focused tests, then run focused native tests and full verification.

## Verification

- `bin/test-fast`
- `cargo test -p ct_core http_route_protocol`
- `cargo test -p ct_core http_route_protocol_mismatch_returns_426`
- `bin/verify`

## Decision Log

- 2026-05-13: Native route matching already had method-gate handling but
  skipped protocol-disallowed path matches, causing 404 on real native HTTP
  requests. This plan closes that shipped-path mismatch before new feature work.

## Handoff

- Native HTTP route protocol mismatches now return `426 Upgrade Required`
  before WAMP/Dart dispatch, with allowed-protocol metadata.
- Verified locally with `bin/test-fast`, focused `ct_core` protocol-gate tests,
  and full `bin/verify`.

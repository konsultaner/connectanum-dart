# Exec Plan: http1-idle-log-cleanliness

Status: complete
Owner: Codex
Created: 2026-05-13
Last updated: 2026-05-13

## Goal

Keep the verification and CI log chain clean by treating expected HTTP/1
keep-alive idle timeouts as normal connection closure, while preserving
diagnostics for malformed requests and real I/O errors.

## Scope

- In scope: native HTTP/1 keep-alive idle timeout logging, focused native tests,
  the generated router-hosted MCP consumer smoke, and verification evidence.
- Out of scope: speculative transport tuning, MCP helper permutations, or
  release publishing changes.

## Files Expected To Change

- `native/transport/ct_core/src/lib.rs`
- `docs/project_state.md`

## Preconditions

- `bin/test-fast` must pass before changing native behavior.

## Plan

1. Confirm the local fast suite is green and identify the source of the
   idle-timeout log noise.
2. Make `serve_http_connection` close quietly on
   `NegotiationError::Timeout`, leaving non-timeout errors visible.
3. Run focused Rust coverage and the generated MCP consumer smoke, checking the
   smoke output for the removed diagnostic.
4. Run full verification, then push and inspect hosted CI if the implementation
   commit is published.

## Verification

- `bin/test-fast`
- `cargo test -p ct_core`
- `run_mcp_consumer_package_smoke` with output checked for idle-timeout
  diagnostics
- `bin/verify`

## Decision Log

- 2026-05-13: The generated MCP consumer smoke left idle HTTP/1 keep-alive
  sockets open long enough for the native idle deadline to close them. That is
  expected connection lifecycle behavior, so printing it as a read error made
  otherwise-clean smoke output look like a failure.

## Handoff

- HTTP/1 keep-alive idle timeouts now close quietly in the native connection
  loop instead of printing read-error diagnostics.
- Verified locally with `bin/test-fast`, `cargo test -p ct_core`, a focused
  generated MCP consumer smoke with output checked for the removed diagnostic,
  and full `bin/verify`.

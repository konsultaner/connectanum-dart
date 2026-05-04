# Exec Plan: Router-Hosted MCP Example Readiness

Status: in progress; local verification clean, hosted evidence pending
Owner: Codex
Created: 2026-05-04
Last updated: 2026-05-04

## Goal

Make the router-hosted MCP path directly runnable and public-documentation
accurate for consumer applications and agents that need to use the package
without relying on private project context.

## Scope

In scope:

- Add a runnable `connectanum_router` example that starts a router-hosted MCP
  endpoint, registers a WAMP procedure through an internal session, and proves
  both direct JSON-RPC and Streamable HTTP tool calls against the live route.
- Update public MCP docs to reflect current router-hosted behavior:
  JSON-RPC `POST`, Streamable HTTP session IDs, POST/SSE responses, GET/SSE
  polling, DELETE session teardown, direct JSON-RPC frontend access, and
  route-authenticated WAMP principals.
- Keep private downstream project names and paths out of public docs and
  examples.
- Bundle project-state updates with the implementation-backed change.

Out of scope:

- Router-hosted resource and prompt surfaces.
- Publishing `connectanum_router` or changing package dependency release order.
- Making router private package dry-run a CI gate while it still has known
  pre-existing package-release blockers.

## Files Expected To Change

- `packages/connectanum_router/example/router_hosted_mcp.dart`
- `packages/connectanum_mcp/README.md`
- `docs/examples.md`
- `docs/project_state.md`
- `docs/exec-plans/2026-05-04-router-hosted-mcp-example-readiness.md`
- `docs/exec-plans/2026-05-04-mcp-package-release-readiness.md`

## Plan

1. Add the runnable router-hosted MCP example and make it usable as a smoke
   check with `--smoke-and-exit`.
2. Align public MCP documentation with implemented router-hosted Streamable
   HTTP and direct JSON behavior.
3. Run focused analysis, package, and smoke checks.
4. Run full local verification before handoff.
5. Push and collect hosted GitHub deployment-chain evidence.

## Verification

- Pre-change `bin/test-fast` passed on 2026-05-04.
- Focused checks passed on 2026-05-04:
  `dart analyze packages/connectanum_router`,
  `dart analyze packages/connectanum_mcp`, and
  `dart run packages/connectanum_router/example/router_hosted_mcp.dart --smoke-and-exit`.
- The focused private package command
  `bin/dart-package-publish-dry-run --include-private connectanum_mcp` reached
  package validation but failed because `packages/connectanum_mcp/README.md` is
  modified in the working tree. Rerun after commit when the package tree is
  clean.
- A broader private `connectanum_router` package dry-run remains out of gate
  scope for this slice because it has pre-existing release-readiness blockers:
  private path dependencies, test fixture secret false positives, and a missing
  router changelog.
- Full local `bin/verify` passed on 2026-05-04 after the example/docs change.
  It included formatting, Rust native/FFI tests, Python package-artifact checks,
  MCP package tests, client tests including MCP Streamable HTTP/direct JSON
  helper coverage, auth-server tests, bench integration tests, the full router
  package tests including router-hosted MCP and `remote_auth_integration_test`,
  zero-copy router checks, and Chrome Dart2Wasm WebSocket transport tests.

## Decision Log

- 2026-05-04: Put the runnable router-hosted MCP smoke in
  `connectanum_router` rather than `connectanum_mcp`, because the MCP package
  must remain router-independent while the example needs a live router endpoint
  and internal session.

## Handoff

In progress. Local verification is clean; post-commit focused package dry-run
and hosted GitHub evidence are pending.

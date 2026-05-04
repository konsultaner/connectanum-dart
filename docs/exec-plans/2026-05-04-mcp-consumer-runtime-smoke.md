# Exec Plan: MCP Consumer Runtime Smoke

Status: local verification complete; hosted evidence pending
Owner: Codex
Created: 2026-05-04
Last updated: 2026-05-04

## Goal

Prove that a neutral downstream Dart package can use only public
`connectanum_client`, `connectanum_mcp`, and `connectanum_router` entrypoints to
host and call a router-backed MCP endpoint, not just resolve imports or
construct API objects.

## Scope

In scope:

- Upgrade the temporary consumer package smoke to start a native router when a
  native runtime library is available.
- Register a WAMP procedure through a public internal router session and expose
  it through a public router-hosted MCP HTTP route.
- Exercise direct JSON-RPC tool listing/calling from the consumer package.
- Exercise initialized Streamable MCP tool listing/calling and WAMP pub/sub
  helper polling from the consumer package.
- Preserve the existing public API construction fallback when no native runtime
  is available.

Out of scope:

- Adding private downstream application references.
- Replacing the canonical router-hosted MCP package example.
- Changing native artifact publishing or package release order.

## Plan

1. Run the pre-change fast baseline.
2. Extend `run_mcp_consumer_package_smoke` so the generated consumer app can
   host a router-backed MCP endpoint with public package APIs.
3. Run the focused consumer smoke.
4. Run `bin/test-fast` and `bin/verify`.
5. Push and collect hosted CI/deployment-chain evidence.

## Verification

- Pre-change `bin/test-fast` passed on 2026-05-04.
- Focused consumer package smoke passed on 2026-05-04:
  `bash -lc 'source bin/common.sh && cd_repo_root && run_mcp_consumer_package_smoke'`.
- Post-change `bin/test-fast` passed on 2026-05-04 and included the upgraded
  runtime consumer package smoke.
- Full local `bin/verify` passed on 2026-05-04. It included formatting, Rust
  native/FFI tests, Python package-artifact checks, MCP package tests, client
  tests, auth-server tests, bench integration tests, the router-hosted MCP
  example smoke, the upgraded consumer runtime smoke, full router package tests
  including router-hosted MCP auth/session coverage, zero-copy router checks,
  and Chrome Dart2Wasm WebSocket transport tests.

## Handoff

Implementation and local verification are complete. Hosted GitHub evidence is
pending after push.

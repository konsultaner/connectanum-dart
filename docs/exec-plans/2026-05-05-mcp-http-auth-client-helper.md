# Exec Plan: MCP HTTP Auth Client Helper

Status: complete; local verification clean; hosted evidence pending
Owner: Codex
Created: 2026-05-05
Last updated: 2026-05-05

## Goal

Make protected router-hosted MCP easier to consume from a downstream
application by moving the Connectanum router HTTP auth bridge handshake into
the public `connectanum_client` MCP surface.

## Context

Router-hosted MCP already supports public and bearer-protected routes, and the
consumer package smoke proves both direct JSON-RPC and Streamable HTTP clients.
The remaining friction was consumer-side token acquisition: the public example
and generated external smoke package both hand-built the two-step `/auth`
challenge and token request.

## Scope

- Add a Dart IO `ConnectanumHttpAuthClient` exported from
  `package:connectanum_client/mcp.dart`.
- Support ticket, WAMP-CRA, SCRAM, generic `AbstractAuthentication` challenge
  flows, refresh-token grants, revocation, typed grant parsing, and typed HTTP
  auth exceptions.
- Refactor downstream-facing MCP smoke/example code to use the public helper
  instead of duplicating raw HTTP auth JSON plumbing.
- Keep the router-hosted MCP endpoint model unchanged: the router still
  provides MCP as configured HTTP routes and reuses the router auth/session
  bridge.

## Verification

- Pre-change `bin/test-fast` passed on 2026-05-05.
- Focused helper test passed on 2026-05-05:
  `dart test packages/connectanum_client/test/mcp/http_auth_client_test.dart -r expanded`.
- Package analyzer passed on 2026-05-05:
  `dart analyze packages/connectanum_client packages/connectanum_router`.
- Router-hosted MCP example smoke passed on 2026-05-05:
  `bash -lc 'source bin/common.sh && cd_repo_root && run_router_hosted_mcp_example_smoke'`.
- External consumer package smoke passed on 2026-05-05:
  `bash -lc 'source bin/common.sh && cd_repo_root && run_mcp_consumer_package_smoke'`.
- Post-change `bin/test-fast` passed on 2026-05-05, including the new helper
  tests, router-hosted MCP example smoke, and generated consumer package smoke.
- Full local `bin/verify` passed on 2026-05-05. It included formatting,
  Rust native/FFI tests, Python package-artifact checks, MCP package tests,
  client tests with the new HTTP auth helper coverage, auth-server tests, bench
  integration tests, the router-hosted MCP example smoke, the generated
  external consumer package smoke using the new helper, full router package
  tests including router-hosted MCP auth/session/batch coverage, zero-copy
  router checks, and Chrome Dart2Wasm WebSocket transport tests.

## Handoff

Implementation and full local verification are complete. Hosted GitHub CI
evidence is pending.

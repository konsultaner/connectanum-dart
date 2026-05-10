# Exec Plan: MCP HTTP Auth Per-Call Header Smoke

Status: complete locally; hosted evidence pending
Owner: Codex
Created: 2026-05-10
Last updated: 2026-05-10

## Context

Router-hosted MCP consumers can attach per-call headers to Streamable HTTP and
direct JSON MCP requests. The HTTP auth bridge is part of the same
consumer-facing flow for protected MCP endpoints, but `ConnectanumHttpAuthClient`
only accepted constructor-wide headers. Consumer applications that need
short-lived trace, routing, or edge-auth metadata should be able to attach those
headers to individual grant, refresh, and revoke calls without replacing the
client-owned JSON HTTP headers.

This slice adds per-call header support to the HTTP auth bridge client and
proves it through focused package tests, the IO entrypoint smoke, and the
neutral generated consumer package smoke.

## Implementation Plan

1. Add optional `headers` parameters to `issueTicketToken`, `issueWampCraToken`,
   `issueScramToken`, `authenticate`, `refreshToken`, and `revokeToken`.
2. Apply constructor-wide headers first and per-call headers second while
   keeping `Accept`, `Content-Type`, and `Content-Length` owned by the auth
   client.
3. Extend focused auth client tests to assert per-call headers are sent on
   challenge/token, refresh, and revoke requests while JSON protocol headers
   remain authoritative.
4. Extend the public IO entrypoint smoke and the generated neutral consumer
   package smoke so package consumers compile and run the auth bridge with
   per-call metadata headers.
5. Run focused tests, generated consumer smoke, `bin/test-fast`, and
   `bin/verify`.
6. Push the implementation and collect hosted GitHub deployment-chain evidence.

## Verification

- Pre-change `bin/test-fast` passed on 2026-05-10.
- Focused `dart test
  packages/connectanum_client/test/mcp/http_auth_client_test.dart -r expanded`
  passed after adding per-call auth headers.
- Focused `dart test packages/connectanum_mcp/test/io_client_export_test.dart
  -r expanded --plain-name "IO entrypoint re-exports HTTP auth helpers for MCP
  sessions"` passed after adding auth header coverage.
- Focused `run_mcp_consumer_package_smoke` passed after adding generated
  consumer use of per-call HTTP auth headers.
- Post-change `bin/test-fast` passed on 2026-05-10.
- Full local `bin/verify` passed on 2026-05-10.

## Decision Log

- Per-call auth headers intentionally compose with constructor-wide headers
  using the same "defaults first, call metadata second" shape used by the MCP
  transport client.
- The auth client keeps JSON framing headers authoritative, so caller metadata
  cannot make the auth bridge send non-JSON requests or stale content lengths.
- Authorization headers remain caller-controlled for auth bridge requests so
  deployments can protect the auth endpoint itself when needed.

## Handoff

Implementation and local verification are complete. Push and hosted
CI/deployment-chain evidence remain.

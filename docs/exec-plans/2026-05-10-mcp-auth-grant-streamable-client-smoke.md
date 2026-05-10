# Exec Plan: MCP Auth Grant Streamable Client Smoke

Status: complete locally; hosted CI and deployment-chain evidence pending
Owner: Codex
Created: 2026-05-10
Last updated: 2026-05-10

## Context

Router-hosted MCP consumers can already issue HTTP auth bridge grants and pass
bearer tokens into `McpStreamableHttpClient.withBearerToken`. That still leaves
consumer applications manually copying grant fields into MCP clients and
skipping token-type validation. Protected Streamable HTTP sessions should accept
the auth bridge grant directly so consumers can hand off the bridge response to
the MCP transport without private project assumptions.

This slice adds an auth-grant constructor for the Streamable HTTP client, rejects
unsupported grant token types before opening a session, and tightens refresh and
revoke token validation on the HTTP auth bridge client.

## Implementation Plan

1. Add `McpStreamableHttpClient.withAuthGrant` for `ConnectanumHttpAuthGrant`
   values and keep the Authorization header owned by the grant handoff.
2. Reject non-Bearer grants locally and reuse existing bearer-token trimming and
   empty-token validation.
3. Reject empty refresh and revoke tokens in `ConnectanumHttpAuthClient` before
   sending bridge requests.
4. Extend focused client tests, the public IO entrypoint smoke, and the neutral
   generated consumer package smoke so consumer code proves the grant handoff
   compiles and runs.
5. Run focused tests, generated consumer smoke, `bin/test-fast`, and
   `bin/verify`.
6. Push the implementation and collect hosted GitHub deployment-chain evidence.

## Verification

- Pre-change `bin/test-fast` passed on 2026-05-10.
- Focused `dart test
  packages/connectanum_client/test/mcp/http_auth_client_test.dart
  packages/connectanum_client/test/mcp/streamable_http_client_test.dart -r
  expanded` passed after adding auth-grant handoff and token validation.
- Focused `dart test packages/connectanum_mcp/test/io_client_export_test.dart
  -r expanded --plain-name "IO entrypoint re-exports HTTP auth helpers for MCP
  sessions"` passed after switching the IO smoke to `withAuthGrant`.
- Focused `bash -lc 'source bin/common.sh; run_mcp_consumer_package_smoke'`
  passed after switching the neutral generated consumer smoke to
  `withAuthGrant`.
- Post-change `bin/test-fast` passed on 2026-05-10.
- Full local `bin/verify` passed on 2026-05-10.

## Decision Log

- `withAuthGrant` only accepts Bearer grants because the current router-hosted
  MCP HTTP authorization path is bearer-token based.
- The grant constructor applies caller headers first and then writes
  `Authorization`, matching `withBearerToken` so stale caller Authorization
  headers cannot override the grant.
- Refresh and revoke tokens are trimmed and rejected when empty so malformed
  bridge lifecycle calls fail locally.

## Handoff

Implementation, focused local smoke evidence, post-change `bin/test-fast`, and
full local `bin/verify` are complete. Push and hosted deployment-chain evidence
remain pending.

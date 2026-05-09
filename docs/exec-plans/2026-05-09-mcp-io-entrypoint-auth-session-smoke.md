# Exec Plan: MCP IO Entrypoint Auth Session Smoke

Status: complete; local verification clean; hosted evidence pending
Owner: Codex
Created: 2026-05-09
Last updated: 2026-05-09

## Goal

Prove that a consumer application depending on `connectanum_mcp` can import
only `package:connectanum_mcp/connectanum_mcp_io.dart`, obtain HTTP auth bridge
bearer credentials, and use those credentials for a Streamable HTTP MCP session
without reaching through private package internals.

## Context

- Current priority is router-hosted MCP and downstream application development
  readiness.
- Router integration and generated consumer smokes already cover the protected
  router-hosted MCP path, but the checked-in IO entrypoint package-boundary test
  did not yet prove the auth helper plus bearer-backed Streamable session path
  from the same public import.
- The previous IO entrypoint slices covered direct WAMP helpers, Streamable
  resource/prompt helpers, and Streamable pub/sub helpers.

## Scope

- Extend `packages/connectanum_mcp/test/io_client_export_test.dart`.
- Add a neutral fake HTTP auth bridge plus bearer-protected MCP endpoint.
- Cover public `ConnectanumHttpAuthClient` ticket grant, refresh, and revoke
  calls imported through `connectanum_mcp_io.dart`.
- Cover `McpStreamableHttpClient.withBearerToken(...)` initialization and a
  session-bound `ping` request using the issued access token.
- Assert the auth request bodies, bearer header, and MCP session header so the
  package-boundary smoke proves auth/session plumbing rather than only type
  visibility.

## Verification

- Pre-change `bin/test-fast` passed on 2026-05-09 with isolated `TMPDIR`.
- Focused `dart test packages/connectanum_mcp/test/io_client_export_test.dart`
  passed on 2026-05-09 with isolated `TMPDIR`.
- Post-change `bin/test-fast` passed on 2026-05-09 with isolated `TMPDIR`.
- Full local `bin/verify` passed on 2026-05-09 with isolated `TMPDIR`.

## Decision Log

- 2026-05-09: Chose this slice because the public IO entrypoint already proved
  direct WAMP, resources/prompts, and pub/sub helpers, while auth helper plus
  bearer-backed Streamable session usage still relied on lower-level client
  tests and generated consumer smoke evidence.

## Handoff

Implementation and full local verification are complete. Commit/push and hosted
CI/deployment-chain evidence remain.

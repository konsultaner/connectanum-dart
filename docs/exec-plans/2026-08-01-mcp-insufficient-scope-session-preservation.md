# Exec Plan: MCP Insufficient-Scope Session Preservation

## Status

Complete.

## Goal

Keep an authenticated Streamable HTTP session usable when a router-hosted MCP
operation returns HTTP 403 for insufficient OAuth scope, so a downstream
application can inspect the challenge, perform step-up authorization, and
cleanly manage the existing session instead of losing its session and resume
cursor locally.

## Scope

- Reproduce the current client behavior with focused POST, GET/SSE, and DELETE
  regressions.
- Preserve `MCP-Session-Id` and `Last-Event-ID` on HTTP 403 responses.
- Keep existing local cleanup for HTTP 401 authorization rejection and HTTP
  404 terminated-session responses.
- Continue parsing `WWW-Authenticate` Bearer challenges so callers can read
  `error="insufficient_scope"`, authoritative scopes, and protected-resource
  metadata.
- Prove the behavior through the public MCP IO entrypoint as well as the
  focused client tests.

## Standards Direction

- MCP 2025-11-25 defines HTTP 403 plus a Bearer
  `error="insufficient_scope"` challenge as the runtime signal for step-up
  authorization.
- Streamable HTTP defines HTTP 404 for a terminated MCP session and requires a
  client receiving that response for an active session to initialize a new
  session.
- Therefore a 403 response is not, by itself, evidence that the MCP session or
  its resumable SSE cursor has expired.

Primary references:

- <https://modelcontextprotocol.io/specification/2025-11-25/basic/authorization>
- <https://modelcontextprotocol.io/specification/2025-11-25/basic/transports>

## Non-Goals

- Automatically launch a browser, request broader scopes, or retry the failed
  operation.
- Mutate the bearer credential owned by an existing client instance.
- Change router-side scope-to-role mapping or OAuth token validation.
- Change direct JSON calls, which intentionally remain independent of active
  Streamable HTTP session state.

## Verification

- Focused `McpStreamableHttpClient` POST, GET/SSE, and DELETE regressions
- Public MCP IO-entrypoint authorization/session regression
- `dart analyze packages/connectanum_client packages/connectanum_mcp`
- `bin/test-fast`
- `bin/verify`

## Progress

- 2026-08-01: Selected this bounded auth/session correctness slice after the
  OAuth grant-persistence lifecycle completed and exact-head hosted CI plus the
  strict deployment-chain audit passed. Reviewed the current MCP authorization
  and Streamable HTTP contracts before implementation.
- 2026-08-01: Added a failing client regression proving that POST, GET/SSE, and
  DELETE 403 responses discarded the active session and resume cursor, then
  changed the Streamable HTTP client to preserve both on 403 while retaining
  cleanup for 401 and 404.
- 2026-08-01: Added public IO-entrypoint coverage and extended the isolated MCP
  client-only consumer smoke to parse an `insufficient_scope` Bearer challenge
  and prove that the active session remains usable for caller-managed step-up.
- 2026-08-01: `dart analyze packages/connectanum_client packages/connectanum_mcp`,
  the 175-test client MCP suite, the 86-test MCP package suite, all 18 public
  package-boundary checks, and the isolated client consumer smoke passed.
- 2026-08-01: Pre-change and post-change `bin/test-fast` passed. Final
  `bin/verify` passed with formatting clean, 113 Rust core tests, 52 FFI tests,
  360 core Dart tests, all 96 benchmark tests, all 377 router tests, the
  package/live MCP smokes, 13 focused native-router tests, and Chrome/Dart2Wasm.

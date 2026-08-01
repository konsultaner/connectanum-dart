# Exec Plan: MCP HTTP-Auth Refresh on the Same Session

## Status

Complete.

## Goal

Let a consumer application apply a refreshed router HTTP-auth Bearer grant to
an existing `McpStreamableHttpClient` before its next request, preserving the
active Streamable HTTP session instead of forcing reinitialization after token
rotation.

## Scope

- Add a public in-place `ConnectanumHttpAuthGrant` replacement API to
  `McpStreamableHttpClient`.
- Reuse the constructor's Bearer type and access-token validation and complete
  validation before changing the active Authorization header.
- Preserve session ID, resume cursor, negotiated protocol, request sequence,
  HTTP client, and connection ownership.
- Keep the router's internal authenticated-session lineage stable while the
  bridge invalidates and replaces linked access and refresh tokens, without
  merging independently issued grants for the same principal.
- Prove successful same-session refresh and atomic rejection of malformed or
  non-Bearer replacements in focused client coverage.
- Prove the contract through the public MCP IO entrypoint, an isolated
  client-only consumer smoke, and the live router-hosted refresh path.

## Protocol Direction

- MCP HTTP authorization applies to every HTTP request, including requests in
  one logical Streamable HTTP session.
- The router HTTP-auth bridge rotates access and refresh tokens. A consumer
  that refreshes proactively must therefore be able to replace the credential
  before sending the next session-scoped request.
- Grant refresh and replacement remain caller-controlled. The client does not
  schedule refreshes, retry requests, or infer an expiry policy.

Primary MCP reference:

- <https://modelcontextprotocol.io/specification/2025-11-25/basic/authorization>

## Non-Goals

- Automatically refresh credentials or retry failed MCP operations.
- Revive a session after an HTTP 401 has already cleared local session state.
- Treat the router HTTP-auth bridge as an interoperable OAuth authorization
  server.
- Merge independently issued credentials for one principal into a shared MCP
  session owner.

## Verification

- Focused `McpStreamableHttpClient` replacement regressions
- Public MCP IO-entrypoint same-session refresh regression
- Isolated MCP client-only consumer package smoke
- Live router-hosted MCP refresh smoke
- `dart analyze packages/connectanum_client packages/connectanum_mcp`
- `bin/test-fast`
- `bin/verify`

## Progress

- 2026-08-01: Selected this slice after OAuth step-up replacement completed.
  The OAuth-specific client can adopt a broader grant, but the router-native
  `ConnectanumHttpAuthClient.refreshToken` result still requires a new MCP
  client even when it represents the same authenticated principal.
- 2026-08-01: The client regression exposed a router-side ownership bug: bridge
  refresh closed the internal session keyed to the rotated access token, so a
  correctly replaced grant received `404 Unknown MCP HTTP session`. Token
  rotation now transfers the original grant-specific cache-key lineage to the
  replacement token while old credentials remain invalid. Focused router,
  public IO, isolated consumer, and live hosted-example coverage passes.
- 2026-08-01: `McpStreamableHttpClient.replaceAuthGrant` now validates and
  applies refreshed bridge grants atomically without changing active session or
  resume state. Final revocation still closes the inherited router session and
  the client's next 401 clears local state, while independently issued grants
  retain isolated session lineages.
- 2026-08-01: Pre-change and post-change `bin/test-fast`, focused client,
  public-entrypoint, and router regressions, workspace analysis, isolated
  client and full consumer smokes, every maintained router-hosted MCP live
  variant, and complete `bin/verify` passed. The full gate included 113 Rust
  core tests, 52 FFI tests, 177 client MCP tests, 86 MCP package tests, all 96
  benchmark tests, the 377-test router suite, 13 focused native-router tests,
  package activation checks, and Chrome/Dart2Wasm.
- 2026-08-01: Commit `7465b48` was pushed to GitLab `origin/master` and GitHub
  `master`. Exact-head GitHub CI `30691195808` and Dart Package Publish Dry Run
  `30691195791` passed on their first attempts. WAMP Profile Benchmarks
  `30691195797` passed on attempt 2 with its artifact upload after attempt 1
  narrowly missed two unchanged Dart AES pub/sub throughput floors without
  transport findings. The strict deployment-chain audit passed with clean CI
  logs and all required branch, workflow, package, benchmark-artifact, and
  registry gates clean.

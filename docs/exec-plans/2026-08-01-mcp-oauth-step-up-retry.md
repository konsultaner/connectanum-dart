# Exec Plan: MCP OAuth Step-Up Retry

## Status

Complete.

## Goal

Let a downstream application apply a newly issued, broader OAuth bearer grant
to an existing Streamable HTTP client and retry an insufficient-scope request
without losing the active MCP session, resume cursor, negotiated protocol, or
HTTP connection ownership.

## Scope

- Add a public in-place OAuth grant replacement API to
  `McpStreamableHttpClient`.
- Accept only unexpired Bearer grants bound to the client's canonical MCP
  endpoint.
- Make validation atomic: a rejected grant must not change the credential or
  any Streamable HTTP state.
- Prove initialize, insufficient-scope challenge parsing, replacement, and
  successful same-session retry with focused client tests.
- Prove the contract through the public MCP IO entrypoint and an isolated
  client-only consumer smoke.

## Standards Direction

- MCP 2025-11-25 requires an access token on every HTTP request, including
  requests belonging to one logical session.
- Its step-up authorization flow directs clients to obtain increased scopes
  and retry the original operation with the new authorization.
- Credential replacement remains caller-controlled: the package will not
  automatically launch authorization, retry operations, or choose retry
  limits.

Primary reference:

- <https://modelcontextprotocol.io/specification/2025-11-25/basic/authorization>

## Non-Goals

- Automatically start authorization or refresh flows after a challenge.
- Automatically retry a failed MCP request.
- Transfer session state between separate client instances.
- Accept raw, unvalidated step-up tokens through this OAuth-specific API.

## Verification

- Focused `McpStreamableHttpClient` step-up and grant-validation regressions
- Public MCP IO-entrypoint step-up regression
- Isolated MCP client-only consumer package smoke
- `dart analyze packages/connectanum_client packages/connectanum_mcp`
- `bin/test-fast`
- `bin/verify`

## Progress

- 2026-08-01: Selected this slice after insufficient-scope responses began
  preserving active Streamable HTTP state. Reviewed the current MCP step-up
  contract and confirmed that the client had no public way to apply the newly
  issued authorization to that retained session.
- 2026-08-01: Pre-change `bin/test-fast` passed.
- 2026-08-01: Added a failing client regression proving that a retained MCP
  session could not adopt the broader OAuth grant required for a step-up retry.
  Added validated in-place grant replacement, with resource-binding and expiry
  checks completing before the active Authorization header changes.
- 2026-08-01: Expanded the public MCP IO-entrypoint regression and isolated
  client-only consumer smoke to initialize with a narrow grant, parse the 403
  challenge, replace it with a broader grant, and retry successfully with the
  same session and resume cursor. Rejected resource-mismatched and expired
  replacements leave the prior credential intact.
- 2026-08-01: Focused regressions, package analysis, the 176-test client MCP
  suite, the 86-test MCP package suite, the compatibility facade, and the
  isolated client-only consumer smoke passed.
- 2026-08-01: Post-change `bin/test-fast` and final `bin/verify` passed. The
  complete gate included formatting, 113 Rust core tests, 52 FFI tests, 360
  core Dart tests, all 96 benchmark tests, all 377 router tests, isolated and
  globally activated package consumers, router-hosted MCP variants, 13 focused
  native-router tests, and Chrome/Dart2Wasm.
- 2026-08-01: Commit `58ae229` was pushed to GitLab `origin/master` and GitHub
  `master`. Exact-head GitHub CI `30687559833`, Dart Package Publish Dry Run
  `30687559834`, and WAMP Profile Benchmarks `30687559837` passed on their
  first attempts, including coverage and benchmark artifact uploads. The
  strict deployment-chain audit passed with clean CI logs and all required
  branch, workflow, package, benchmark-artifact, and registry gates clean.

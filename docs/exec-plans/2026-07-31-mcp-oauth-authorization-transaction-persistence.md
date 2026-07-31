# Exec Plan: MCP OAuth Authorization Transaction Persistence

## Status

Complete.

## Goal

Let downstream Dart and Flutter applications persist a pending MCP OAuth
authorization transaction across application lifecycle boundaries and restore
the exact validated request needed for callback state and PKCE verification,
without inventing a private serialization format.

## Scope

- Add a versioned, JSON-compatible public transaction representation around
  `McpAuthorizationRequest`.
- Persist only the validated inputs needed to rebuild the authorization URI:
  authorization-server metadata, resource, client ID, redirect URI, scopes,
  state, and PKCE verifier.
- Record creation and expiration timestamps, reject non-positive lifetimes,
  and refuse restoration after the explicit expiry.
- Revalidate all persisted values and rebuild the authorization URI instead of
  trusting a stored URI.
- Keep parsing and expiry failures typed and redacted so state, PKCE verifiers,
  authorization query data, and storage payloads do not reach exception text.
- Prove JSON encode/decode restoration through focused client tests, the MCP IO
  package entrypoint, and the generated consumer-package lifecycle smoke.

## Standards Direction

- RFC 8252 requires pending authorization responses to match the state of an
  outgoing native-app request. Persisting that pending transaction therefore
  includes both the generated state and the PKCE verifier.
- RFC 9700 treats PKCE verifier and token material as security-sensitive. The
  persistence document is explicitly suitable only for caller-selected secure
  storage and must not be logged or included in diagnostic strings.
- The MCP authorization specification requires refresh-token confidentiality
  in storage. This slice does not choose a filesystem, keychain, database, or
  Flutter storage package; the same caller-owned secure-storage boundary will
  apply to later registration and grant persistence.

Primary references:

- <https://modelcontextprotocol.io/specification/2025-11-25/basic/authorization>
- <https://www.rfc-editor.org/rfc/rfc8252.html>
- <https://www.rfc-editor.org/rfc/rfc9700.html>

## Non-Goals

- Add a concrete filesystem, keychain, credential-vault, or Flutter plugin.
- Persist dynamic client registrations or bearer/refresh-token grants in the
  same slice.
- Keep a loopback listener alive across process termination or prescribe
  platform application-lifecycle behavior.
- Relax callback state, redirect, resource, PKCE, or authorization-server
  validation.

## Verification

- Focused round-trip, expiration, schema, tamper, and redaction regressions
- Public MCP IO-entrypoint lifecycle regression
- Isolated client consumer-package smoke
- `dart analyze packages/connectanum_client packages/connectanum_mcp`
- `bin/test-fast`
- `bin/verify`

## Progress

- 2026-07-31: Pre-change `bin/test-fast` completed through analysis, package
  suites, generated consumers, router-hosted MCP variants, router CLI consumer
  coverage, and focused native-router checks.
- 2026-07-31: Added `McpOAuthAuthorizationTransaction`, the versioned JSON
  representation, explicit creation/expiry bounds, redacted state failures,
  metadata revalidation, and authorization URI reconstruction from validated
  persisted fields.
- 2026-07-31: Added focused round-trip, expiry, clock, schema, tamper, and
  redaction coverage. The public MCP IO lifecycle and generated client-only
  consumer smoke now serialize and restore the pending request before the
  external-user-agent callback and token exchange.
- 2026-07-31: Focused analysis, 169 client MCP tests, 85 MCP package tests, all
  18 package-boundary guards, and the isolated and globally activated client
  consumer smoke passed.
- 2026-07-31: Post-change `bin/test-fast` passed, including 360 core Dart
  tests, 85 MCP tests, 169 client MCP tests, all 96 benchmark tests, generated
  package consumers, every router-hosted MCP mode, router CLI consumer
  coverage, and focused native-router auth/session tests.
- 2026-07-31: Complete local `bin/verify` passed, including formatting for 393
  Dart files, 113 Rust core tests, 52 FFI tests, 360 core Dart tests, 85 MCP
  tests, 169 client MCP tests, all 96 benchmark tests, the complete 377-test
  router suite, generated and globally activated package consumers, all
  router-hosted MCP smoke modes, 13 focused native-router tests, and
  Chrome/Dart2Wasm.
- 2026-07-31: Commit `bb4ac84` was pushed to both `master` remotes. Exact-head
  GitHub CI `30646387600`, Dart Package Publish Dry Run `30646387630`, and WAMP
  Profile Benchmarks `30646387579` passed on their first attempts. CI included
  Fast Checks, Full Verify, Dart VM Coverage, Codecov upload, and the coverage
  artifact; the WAMP run uploaded its benchmark artifact. The strict
  deployment-chain audit passed with clean exact-head CI logs and all required
  branch, workflow, package, benchmark-artifact, and registry gates clean.

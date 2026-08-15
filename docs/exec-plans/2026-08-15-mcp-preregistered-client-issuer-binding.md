# Exec Plan: MCP Pre-Registered Client Issuer Binding

Status: implementation complete; local verification green; hosted evidence pending
Owner: Codex
Created: 2026-08-15
Last updated: 2026-08-15

## Goal

Prevent a downstream application from sending an MCP OAuth client identity or
secret to an authorization server other than the validated issuer for which
the client was pre-registered or dynamically registered.

## Scope

- In scope:
  - Bind pre-registered public and confidential client authentication to
    validated authorization-server metadata.
  - Preserve the issuer portability of HTTPS Client ID Metadata Documents.
  - Carry the existing Dynamic Client Registration issuer into its public
    token-endpoint authentication object.
  - Reject missing or mismatched issuer bindings before authorization-code
    exchange, refresh, or revocation opens an HTTP request.
  - Prove the boundary through focused, public IO, and isolated installed-
    package coverage without private project assumptions.
- Out of scope:
  - Automatically choosing among pre-registration, Client ID Metadata
    Documents, and deprecated Dynamic Client Registration.
  - Persisting pre-registered client secrets.
  - Selecting secure storage or changing token refresh scheduling.

## Preconditions

- Commit `a5088388` is published to both maintained `master` branches and its
  exact-head deployment-chain evidence is green.
- The existing hosted-evidence notes are docs-only and will be bundled with
  this implementation.
- Pre-change `bin/test-fast` exits zero across the maintained repository,
  live-WAMP, executable, and consumer-smoke matrix.

## Plan

1. Add fail-first token lifecycle coverage for missing and mismatched issuer
   bindings with zero opened HTTP requests.
2. Add the public issuer-bound authentication contract and wire Dynamic Client
   Registration plus Client ID Metadata Documents through it.
3. Extend public IO and generated installed-package evidence.
4. Run focused checks and `bin/verify`, then update durable state.
5. Commit and push the implementation, then collect exact-head hosted and
   strict deployment-chain evidence for the affected public package paths.

## Verification

- Focused OAuth token exchange, registration, and client metadata tests.
- Public MCP IO entrypoint test and generated installed-package consumer smoke.
- Affected package analysis and shell/Python validation.
- `bin/verify`.

## Verification Evidence

- Fail-first token coverage initially failed to load because the issuer-bound
  registered-public factory did not exist.
- The focused OAuth token, dynamic registration, Client ID Metadata Document,
  Streamable HTTP lifecycle, and public IO matrix passes, including zero opened
  token or revocation requests for unbound and mismatched identities and an
  explicit confidential-secret cross-issuer rejection.
- The isolated client-only installed-package smoke passes with direct
  pre-registered and persisted Dynamic Client Registration issuer-binding
  assertions.
- `bin/verify` exits zero with formatting unchanged; Rust core and FFI green;
  366 core tests; 116 MCP tests; the complete 293-case MCP/client suite; 97
  benchmark tests including all 37 live WAMP workloads; the 442-case router
  suite; six remote-auth tests; 13 native follow-ups; every maintained consumer
  smoke; Chrome; and Dart2Wasm green.

## Decision Log

- 2026-08-15: Stable MCP `2026-07-28` requires pre-registered and persisted
  dynamically registered credentials to remain associated with the exact
  authorization-server issuer. The current public authentication value carries
  only a client ID, method, and optional secret, so a consuming application can
  accidentally reuse it after selecting or discovering another issuer.
- 2026-08-15: HTTPS Client ID Metadata Document identities remain portable
  because the authorization server resolves the document on demand. The
  fail-closed issuer requirement therefore applies to non-CIMD identities,
  while CIMD use is validated against advertised server support.

## Handoff

- `McpOAuthClientAuthentication.registeredPublic`, `clientSecretBasic`, and
  `clientSecretPost` capture the exact validated authorization-server issuer.
  `none` is reserved for portable HTTPS Client ID Metadata Document identities
  against servers that advertise that feature.
- Authorization-code exchange, refresh, and revocation reject missing or
  mismatched bindings before opening an HTTP request. Dynamic Client
  Registration derives the binding from its persisted authorization-server
  metadata.
- Commit, push, exact-head hosted workflows, and the strict deployment-chain
  audit remain pending.

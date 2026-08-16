# Exec Plan: MCP Challenge Auth-Endpoint Resolution

Status: active
Owner: Codex
Created: 2026-08-16
Last updated: 2026-08-16

## Goal

Let a public consumer safely construct the Connectanum HTTP auth client from a
router-hosted MCP Bearer challenge, including a compatible alternate auth
route, without hard-coding a second endpoint or allowing credentials to cross
the MCP endpoint's origin.

## Scope

- In scope:
  - expose the router `auth_path` Bearer parameter through the typed public
    challenge API;
  - add a public `ConnectanumHttpAuthClient` construction path that accepts an
    MCP endpoint and Bearer challenge;
  - require an absolute-path, query-free, fragment-free auth reference and an
    absolute HTTP(S) MCP endpoint without embedded credentials;
  - prove alternate compatible auth-route discovery in focused tests and the
    isolated neutral router CLI consumer smoke.
- Out of scope:
  - OAuth authorization-server discovery or token exchange changes;
  - cross-origin HTTP auth bridges;
  - automatic credential selection or persistence.

## Files Expected To Change

- `packages/connectanum_client/lib/src/mcp/authorization_discovery.dart`
- `packages/connectanum_client/lib/src/mcp/http_auth_client.dart`
- `packages/connectanum_client/test/mcp/authorization_discovery_test.dart`
- `packages/connectanum_client/test/mcp/http_auth_client_test.dart`
- `bin/common.sh`
- `docs/project_state.md`
- `ROADMAP.md`

## Preconditions

- The scheduled launchd wrapper, its current Codex child, and its live run lock
  are the expected current run; no unrelated process is editing this repo.
- The inherited documentation-only exact-head evidence for commit `6882c00b`
  remains intentional and will be bundled with this implementation.
- Pre-change `bin/test-fast` passes on 2026-08-16.

## Plan

1. Add fail-first challenge parsing and endpoint-safety regressions.
2. Implement typed `auth_path` access plus same-origin public auth-client
   construction.
3. Extend the generated neutral consumer to discover and use a compatible
   alternate router auth route, then run focused, fast, and canonical
   verification.
4. Record the material milestone, commit and publish it, and collect exact-head
   hosted workflow and strict deployment-chain evidence.

## Verification

- `dart test packages/connectanum_client/test/mcp/authorization_discovery_test.dart packages/connectanum_client/test/mcp/http_auth_client_test.dart`
- `bin/test-fast`
- `bin/verify`
- Exact-head hosted CI and deployment-chain strict audit after publication.

## Decision Log

- 2026-08-16: Selected this as the next shipped-path readiness gap because the
  router can advertise a compatible alternate `auth_path`, while consumers
  still have to hard-code the HTTP auth endpoint separately.
- 2026-08-16: Restrict challenge resolution to same-origin absolute paths with
  no query or fragment. This follows the router contract and prevents an
  untrusted challenge from redirecting auth secrets to another authority or
  placing them beside attacker-controlled URL data.

## Progress

- 2026-08-16: The focused regression first failed because
  `McpBearerChallenge.authPath` and
  `ConnectanumHttpAuthClient.fromMcpBearerChallenge` did not exist.
- 2026-08-16: The typed challenge accessor and public auth-client factory now
  pass all 33 focused authorization discovery/auth-client tests. Client package
  analysis is clean.
- 2026-08-16: The isolated neutral router CLI consumer advertises a compatible
  `/auth/discovered` route ahead of the fallback route, obtains the protected
  MCP challenge without creating session or resume state, constructs the auth
  client from that challenge, issues and refreshes the route-bound grant, and
  completes the existing protected direct JSON, Streamable HTTP, WAMP meta,
  pub/sub, and revocation matrix.
- 2026-08-16: Post-change `bin/test-fast` passes. Canonical `bin/verify` passes
  with zero formatting changes, 117 Rust core/serializer tests, 52 native FFI
  tests, the feature-gated native metrics snapshot, 366 Dart core tests, 116
  MCP tests, the complete 296-case MCP/client suite, all 97 benchmark tests
  including 37 live WAMP workloads, all 454 router cases, six remote-auth
  tests, 13 native follow-ups, every maintained consumer/global-activation
  smoke, Chrome, and Dart2Wasm.

## Handoff

- Implementation and all local verification are complete; publication,
  exact-head hosted workflows, and the strict deployment-chain audit remain.

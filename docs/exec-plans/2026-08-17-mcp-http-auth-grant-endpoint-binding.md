# Exec Plan: MCP HTTP-Auth Grant Endpoint Binding

Status: active
Owner: Codex
Created: 2026-08-17
Last updated: 2026-08-17

## Goal

Prevent downstream applications from disclosing a router-issued access or
refresh credential to a different HTTP-auth endpoint when reusing a public
grant for refresh or revocation.

## Scope

- In scope:
  - attach the issuing HTTP-auth endpoint to grants returned by the public
    client;
  - reject grant-aware refresh against a different or unknown endpoint before
    network I/O;
  - add endpoint-bound grant-aware revocation for access and refresh tokens;
  - retain raw token refresh/revocation operations for compatibility and
    explicit invalid-token testing;
  - migrate maintained successful consumer lifecycles to grant-aware
    revocation;
  - preserve direct JSON, Streamable HTTP, WAMP meta, pub/sub, and package
    boundary smoke behavior.
- Out of scope:
  - changing router-side listener/auth-route grant binding;
  - durable grant persistence or storage selection;
  - removing raw token operations.

## Files Expected To Change

- `packages/connectanum_client/lib/src/mcp/http_auth_client.dart`
- `packages/connectanum_client/test/mcp/http_auth_client_test.dart`
- `packages/connectanum_client/test/mcp/http_auth_client_lifecycle_test.dart`
- `packages/connectanum_client/CHANGELOG.md`
- `packages/connectanum_mcp/lib/src/cli/router_hosted_client.dart`
- `packages/connectanum_mcp/test/io_client_export_test.dart`
- `packages/connectanum_mcp/CHANGELOG.md`
- `packages/connectanum_router/example/router_hosted_mcp.dart`
- `bin/common.sh`
- `tool/test_mcp_consumer_package_boundary.py`
- `docs/project_state.md`

## Preconditions

- The scheduled launchd wrapper and its current Codex child are the expected
  run; no unrelated process is editing this repository.
- Commit `d2aaf1ef` and both feature-branch remotes are aligned.
- The preceding slice's hosted-evidence documentation is the only inherited
  working-tree change and will be bundled with this implementation.
- Exact-head GitHub CI and package dry-run workflows are green.

## Plan

1. Add fail-first public-client regressions proving that a grant from one
   endpoint is not refreshed or revoked through another endpoint.
2. Stamp public-client grants with their exact issuing endpoint and validate
   that provenance before grant-aware credential operations.
3. Add access/refresh token selection for grant-aware revocation and migrate
   maintained successful consumer lifecycles to it.
4. Run focused client/package tests and maintained consumer smokes.
5. Run `bin/verify`, review, publish, and collect exact-head hosted evidence.

## Verification

- focused HTTP-auth client and lifecycle tests
- public MCP IO package tests
- generated consumer structural boundary checks
- source and globally activated router-hosted client smokes
- isolated generated downstream application smokes
- `bin/test-fast`
- `bin/verify`
- strict release-ready package dry run
- exact-head hosted workflows after publication

## Decision Log

- 2026-08-17: Selected this slice because server-side route binding rejects a
  misplaced credential only after the client has transmitted it. Public
  grant-aware operations must enforce the issuing endpoint before I/O.
- 2026-08-17: Keep raw token operations explicitly unbound for compatibility
  and negative tests; maintained successful lifecycles use bound grants.

## Progress

- 2026-08-17: Serena preflight, onboarding, overlap checks, project-state and
  roadmap review pass. Only the preceding slice's intentional hosted-evidence
  documentation is modified at startup.
- 2026-08-17: Pre-change `bin/test-fast` passes the complete fast regression
  matrix: 366 core tests, 117 MCP package tests, the 309-case client/MCP suite,
  all 97 benchmark tests including 37 live WAMP workloads, and every maintained
  isolated, generated, source, globally activated, and router CLI smoke.
- 2026-08-17: A fail-first public-client regression proves that a grant issued
  by one auth endpoint was transmitted to a different endpoint before the
  router rejected it. Client-issued grants now retain their exact issuing
  endpoint, and grant-aware refresh and access/refresh revocation validate that
  provenance before selecting or transmitting a credential.
- 2026-08-17: Maintained package, router example, generated downstream, and
  router CLI success paths use grant-aware revocation. A raw policy-proof grant
  parser now explicitly preserves its issuing endpoint; raw token APIs remain
  covered for deliberate compatibility and invalid-token checks.
- 2026-08-17: Focused HTTP-auth and lifecycle tests pass all 35 cases, the
  public MCP IO lifecycle test passes, affected-package analysis is clean, all
  23 package-boundary checks pass, and the client-only, generated downstream,
  source/globally activated client, router example, and router CLI consumer
  smokes pass. The router CLI smoke caught and verified the policy-proof parser
  migration before full verification.
- 2026-08-17: Canonical `bin/verify` passes with zero formatting changes, 117
  Rust core/serializer checks, all 52 FFI tests plus metrics mode, 366 Dart core
  tests, 117 MCP package tests, the complete 312-case client/MCP suite, all 97
  benchmark tests with 37 live WAMP workloads, all 454 router tests, six
  remote-auth tests, 13 native follow-ups, every maintained isolated and
  globally activated consumer smoke, Chrome, and Dart2Wasm. The strict 20-case
  release-ready package dry run and 22-case deployment-audit regression suite
  also pass.

## Handoff

- Active. Implementation and local verification are complete; publication,
  exact-head hosted workflows, and deployment-chain audits remain.

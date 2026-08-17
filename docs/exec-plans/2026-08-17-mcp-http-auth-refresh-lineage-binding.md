# Exec Plan: MCP HTTP-Auth Refresh Lineage Binding

Status: active
Owner: Codex
Created: 2026-08-17
Last updated: 2026-08-17

## Goal

Give downstream applications a public router HTTP-auth refresh path that
fails closed when a replacement grant changes the authenticated or authorized
lineage of the grant being refreshed.

## Scope

- In scope:
  - add a grant-aware refresh operation without removing the existing
    raw-token compatibility surface;
  - require a usable refresh token and complete router-issued identity on the
    prior grant before network I/O;
  - bind refreshed realm, auth method, auth ID, auth role, provider, token
    scheme, and JSON details to the prior grant;
  - keep untrusted response values out of protocol failures;
  - migrate maintained consumer lifecycles to the grant-aware operation;
  - preserve direct JSON, Streamable HTTP, WAMP meta, pub/sub, refresh/revoke,
    and package-boundary smoke behavior.
- Out of scope:
  - changing router token issuance or rotation policy;
  - removing the raw refresh-token API;
  - defining application policy for deliberately changing authorization
    context, which requires fresh authentication rather than refresh.

## Files Expected To Change

- `packages/connectanum_client/lib/src/mcp/http_auth_client.dart`
- `packages/connectanum_client/test/mcp/http_auth_client_test.dart`
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
- Commit `f75bc960` and both feature-branch remotes are aligned.
- The preceding slice's hosted-evidence documentation is the only inherited
  working-tree change and will be bundled with this implementation.
- Exact-head GitHub CI and package dry-run workflows are green.
- Pre-change `bin/test-fast` passes.

## Plan

1. Add fail-first public-client regressions for complete refresh-lineage
   continuity and redacted drift failures.
2. Add a public grant-aware refresh operation that validates the prior grant
   before I/O and the replacement grant before returning it.
3. Move maintained public and generated consumer lifecycles to the bound
   operation while retaining raw-token calls for explicit low-level cases.
4. Run focused client/package tests and maintained consumer smokes.
5. Run `bin/verify`, review, publish, and collect exact-head hosted evidence.

## Verification

- focused HTTP-auth client tests
- public MCP IO package tests
- generated consumer structural boundary checks
- source and globally activated router-hosted client smokes
- isolated generated downstream application smokes
- `bin/test-fast`
- `bin/verify`
- strict release-ready package dry run
- exact-head hosted workflows after publication

## Decision Log

- 2026-08-17: Selected this slice because router refresh responses preserve
  the complete issued authorization context, while the public raw-token
  refresh operation has no prior grant with which to validate that context.
- 2026-08-17: Keep the raw-token operation for compatibility and invalid-token
  testing, but make the additive grant-aware operation the maintained consumer
  path, matching the public OAuth refresh API's grant-bound shape.

## Progress

- 2026-08-17: Serena preflight, onboarding, overlap checks, project-state and
  roadmap review pass. Only the preceding slice's intentional hosted-evidence
  documentation is modified at startup.
- 2026-08-17: Pre-change `bin/test-fast` passes the complete fast matrix,
  including 366 core tests, 117 MCP package tests, the 306-case client/MCP
  suite, all 97 benchmark tests and 37 live WAMP workloads, every maintained
  router-hosted and generated consumer smoke, and focused router auth/session
  checks.
- 2026-08-17: Fail-first regressions cover successful JSON-semantic lineage
  continuity, redacted drift rejection for token scheme, realm, method, auth
  ID, role, provider, and details, plus complete prior-grant validation before
  I/O. The public client now exposes `refreshGrant` while retaining the
  raw-token compatibility operation.
- 2026-08-17: Maintained package, source, global-executable, generated consumer,
  and router CLI lifecycles now use the bound operation for successful,
  rotated, overlapping, and revoked refreshes. Focused client/lifecycle/IO
  tests pass all 47 cases, affected-package analysis is clean, all 23 consumer
  boundary checks pass, and every affected isolated and router-hosted live
  smoke passes.
- 2026-08-17: Canonical `bin/verify` passes with zero formatting changes, 117
  Rust core/serializer checks, all 52 FFI tests plus metrics mode, 366 Dart
  core tests, 117 MCP package tests, the complete 309-case client/MCP suite,
  all 97 benchmark tests with 37 live WAMP workloads, the complete 454-case
  router suite, six remote-auth tests, 13 native follow-ups, every maintained
  isolated and globally activated consumer smoke, Chrome, and Dart2Wasm. The
  strict 20-case release-ready package dry run and 22-case deployment-audit
  regression suite also pass.

## Handoff

- Active. Implementation and local verification are complete; publication,
  exact-head hosted workflows, and the strict deployment-chain audit remain.

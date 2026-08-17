# Exec Plan: MCP HTTP-Auth Response Binding

Status: completed
Owner: Codex
Created: 2026-08-16
Last updated: 2026-08-17

## Goal

Make the public router HTTP-auth client fail closed when a challenge or issued
grant does not describe the realm, authentication method, and identity that the
consumer requested, before those credentials can be used with router-hosted
MCP.

## Scope

- In scope:
  - reproduce challenge realm/method drift before the client signs a response;
  - reproduce issued-grant realm/method/auth-id drift before the client returns
    bearer credentials;
  - validate the router-provided response identity without including untrusted
    values in failures;
  - preserve the existing ticket, WAMP-CRA, SCRAM, refresh/revoke, direct JSON,
    Streamable HTTP, WAMP meta, and pub/sub positive paths.
- Out of scope:
  - changing router challenge or grant response fields;
  - changing OAuth identity/resource binding;
  - defining application policy for intentionally changing identities during a
    refresh operation.

## Files Expected To Change

- `packages/connectanum_client/lib/src/mcp/http_auth_client.dart`
- `packages/connectanum_client/CHANGELOG.md`
- `packages/connectanum_client/test/mcp/http_auth_client_lifecycle_test.dart`
- `packages/connectanum_client/test/mcp/http_auth_client_test.dart`
- `packages/connectanum_client/test/mcp/http_auth_discovery_test.dart`
- `packages/connectanum_mcp/CHANGELOG.md`
- `packages/connectanum_mcp/test/io_client_export_test.dart`
- `bin/common.sh`
- `tool/test_mcp_consumer_package_boundary.py`
- `docs/project_state.md`

## Preconditions

- The scheduled launchd wrapper and its current Codex child are the expected
  run; no unrelated process is editing this repository.
- Commit `6dea11e3` and both feature-branch remotes are aligned.
- The inherited documentation-only hosted evidence remains intentional and
  will be bundled with this implementation.
- Exact-head GitHub CI and package dry-run workflows are green.
- Pre-change `bin/test-fast` passes.

## Plan

1. Add fail-first public-client regressions for challenge and grant identity
   drift.
2. Bind every challenge to the requested realm and authentication method before
   invoking the secret-bearing authentication response.
3. Bind every successful issued grant to the requested realm, authentication
   method, and auth ID before returning it.
4. Run focused client/package tests and maintained consumer smokes.
5. Run `bin/verify`, review, publish, and collect exact-head hosted evidence.

## Verification

- focused HTTP-auth client tests
- complete `connectanum_client` MCP tests
- public MCP IO package tests
- generated and maintained router-hosted client smokes
- `bin/test-fast`
- `bin/verify`
- strict release-ready package dry run
- exact-head hosted workflows after publication

## Decision Log

- 2026-08-16: Selected this slice because the router already returns
  authoritative `realm` and `authmethod` challenge fields plus
  `realm`/`authmethod`/`authid` grant fields, while the public client currently
  accepts them without comparing them to its request.
- 2026-08-16: Treat identity drift as a protocol failure and keep untrusted
  response values out of the exception text.
- 2026-08-17: Require generated positive consumer fixtures to reproduce the
  real router challenge fields. Keep a structural package-boundary assertion
  alongside the live smoke so fixture drift fails before the generated
  application runs.

## Progress

- 2026-08-16: Serena preflight, onboarding, overlap checks, state and roadmap
  review pass. Only the preceding slice's expected post-push evidence files are
  modified at startup.
- 2026-08-16: Pre-change `bin/test-fast` passes the complete fast matrix,
  including 366 core tests, 117 MCP package tests, the 304-case client/MCP
  suite, all 97 benchmark tests and 37 live WAMP workloads, every maintained
  source/global router-hosted MCP smoke, and the generated consumer
  applications.
- 2026-08-17: Fail-first regressions reproduce challenge realm/method drift
  before signing and grant realm/method/auth-id drift before returning bearer
  credentials. The public client now validates those bindings with redacted
  typed protocol failures. Focused HTTP-auth/discovery/lifecycle/public-IO
  tests pass, the combined client MCP and public MCP suite passes all 423
  cases, affected-package analysis is clean, and all 23 generated-consumer
  boundary checks pass.
- 2026-08-17: The first full gate correctly exposed an outdated generated
  client-only challenge fixture that omitted the router's `realm` and
  `authmethod`. The fixture and its structural regression were corrected; the
  standalone source/global client-only smoke and generated downstream
  application smoke pass.
- 2026-08-17: Canonical `bin/verify` passes on the corrected tree with zero
  formatting changes, 117 Rust core/serializer checks, all 52 FFI tests plus
  the metrics test mode, 366 Dart core tests, 117 MCP package tests, the
  complete 306-case client/MCP suite, all 97 benchmark tests with 37 live WAMP
  workloads, all 454 router cases, six remote-auth tests, 13 native follow-ups,
  every maintained isolated and globally activated consumer smoke, Chrome,
  and Dart2Wasm.
- 2026-08-17: The clean strict release-ready package dry run validates all
  seven synchronized `3.0.0-beta` archives, public executables, and release
  ordering with zero warnings. Commit `f75bc960` is published to both
  maintained feature-branch remotes.
- 2026-08-17: Exact-head GitHub `CI` run `31976621727` passes Fast Checks,
  Full Verify, and Dart VM Coverage with retained coverage artifact
  `9271444968`. Dart Package Publish Dry Run `31976621678` passes. The strict
  protected-release baseline passes against `master`, and the feature-branch
  audit confirms exact-head CI/job/log cleanliness, workflow and router-package
  visibility, and current package-run relevance.

## Handoff

- Completed. The implementation, local verification, strict package dry run,
  publication, exact-head hosted workflows, and deployment-chain audits pass.

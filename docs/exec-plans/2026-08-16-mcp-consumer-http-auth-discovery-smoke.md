# Exec Plan: MCP Consumer HTTP-Auth Discovery Smoke

Status: active
Owner: Codex
Created: 2026-08-16
Last updated: 2026-08-16

## Goal

Prove that a standalone downstream application can discover a router-provided
HTTP-auth endpoint from its protected MCP endpoint, configure auth-request
headers without leaking them into the credential-free discovery probe, obtain a
grant, and continue through the existing direct JSON and Streamable HTTP
lifecycle.

## Scope

- In scope:
  - let `discoverHttpAuthClient` configure default headers on the returned auth
    client while keeping the probe header-free;
  - add focused fail-first coverage for that isolation boundary;
  - replace the generated MCP client consumer's hard-coded auth endpoint and
    the generated real-router consumer's private challenge probe with public
    discovery;
  - require the generated fixtures to advertise and validate the discovered
    realm and `auth_path` before its existing grant, refresh/revoke, direct JSON,
    Streamable HTTP, WAMP meta, and pub/sub checks.
- Out of scope:
  - forwarding credentials or caller headers to the discovery probe;
  - changing router challenge semantics;
  - adding new authentication methods or OAuth interaction policy.

## Files Expected To Change

- `packages/connectanum_client/lib/src/mcp/streamable_http_client.dart`
- `packages/connectanum_client/test/mcp/http_auth_discovery_test.dart`
- `bin/common.sh`
- `tool/test_mcp_consumer_package_boundary.py`
- `docs/project_state.md`

## Preconditions

- The scheduled launchd wrapper and its current Codex child are the expected
  run; no unrelated process is editing this repository.
- Commit `0a643840` and both feature-branch remotes are aligned.
- The inherited documentation-only hosted evidence remains intentional and
  will be bundled with this implementation.
- Exact-head GitHub CI and package dry-run workflows are green.
- Pre-change `bin/test-fast` passes.

## Plan

1. Add fail-first unit and structural consumer-boundary checks for auth-only
   default headers and public discovery use.
2. Extend the public helper without weakening the credential-free probe.
3. Move the generated consumer package onto the discovered endpoint and retain
   its existing authenticated MCP lifecycle assertions.
4. Run focused client, structural, and generated-package smoke checks.
5. Run `bin/verify`, review, publish, and collect exact-head hosted evidence.

## Verification

- focused HTTP-auth discovery tests
- public consumer structural contracts
- generated MCP client package smoke
- `bin/test-fast`
- `bin/verify`
- strict release-ready package dry run
- exact-head hosted workflows after publication

## Decision Log

- 2026-08-16: Selected this slice because the public helper is covered through
  unit tests and the published CLI, while one neutral generated application
  still hard-codes `/auth` and the real-router consumer duplicates the private
  probe, so neither directly proves the complete public-package boundary.
- 2026-08-16: Treat configured headers as auth-client defaults only. Discovery
  remains a fresh credential-free, sessionless, caller-header-free probe.

## Progress

- 2026-08-16: Serena preflight, onboarding, overlap checks, state and roadmap
  review pass. Only the preceding slice's expected post-push evidence files are
  modified at startup.
- 2026-08-16: Pre-change `bin/test-fast` passes the complete fast matrix,
  including 117 MCP package tests, the 304-case client/MCP suite, all 97
  benchmark tests and 37 live WAMP workloads, source/global router-hosted MCP
  smokes, and both generated consumer applications.
- 2026-08-16: Fail-first Dart coverage rejects the missing `headers` parameter,
  and the structural consumer contract rejects both the standalone fixture's
  hard-coded auth endpoint and the real-router fixture's private challenge
  probe. The public helper now applies configured headers only to the returned
  auth client; its fresh sessionless probe receives none of them.
- 2026-08-16: Eight focused discovery tests, the 304-case client/MCP suite, all
  117 MCP package tests, 23 consumer-boundary checks, affected-package
  analysis, and the isolated standalone generated consumer pass. The
  real-router generated consumer also passes its complete public/protected
  auth, direct JSON, Streamable HTTP, WAMP meta, resource/prompt, and pub/sub
  matrix after replacing its private helper with the public discovery API.
- 2026-08-16: Canonical `bin/verify` passes with zero formatting changes, 117
  Rust core/serializer checks, all 52 FFI tests plus the metrics test mode, 366
  Dart core tests, 117 MCP package tests, the 304-case client/MCP suite, all 97
  benchmark tests with 37 live WAMP workloads, the 454-case router suite, six
  remote-auth tests, 13 native follow-ups, every maintained isolated and
  globally activated consumer smoke, Chrome, and Dart2Wasm.

## Handoff

- Active. Implementation and all local verification pass; publication, the
  clean strict package dry run, and exact-head hosted evidence remain.

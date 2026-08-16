# Exec Plan: MCP Public HTTP-Auth Discovery Helper

Status: active
Owner: Codex
Created: 2026-08-16
Last updated: 2026-08-16

## Goal

Let a downstream application construct a router HTTP-auth client directly from
a protected MCP endpoint and requested realm without reproducing the published
CLI's private credential-free probe, challenge selection, and same-origin
`auth_path` handling.

## Scope

- In scope:
  - add a public `connectanum_client` discovery helper that probes without
    credentials or MCP session state;
  - require HTTP 401 plus a realm-matched Bearer challenge with `auth_path`;
  - reuse the existing same-origin auth-path validation and explicit HTTP
    client ownership contract;
  - refactor the published `router_hosted_client` executable onto that helper;
  - prove the helper with focused tests and an isolated public-package path.
- Out of scope:
  - changing router challenge or grant semantics;
  - OAuth browser authorization;
  - choosing or storing downstream credentials.

## Files Expected To Change

- `packages/connectanum_client/lib/src/mcp/streamable_http_client.dart`
- `packages/connectanum_client/test/mcp/http_auth_discovery_test.dart`
- `packages/connectanum_mcp/lib/src/cli/router_hosted_client.dart`
- `packages/connectanum_mcp/test/io_client_export_test.dart`
- `tool/test_mcp_consumer_package_boundary.py`
- `docs/project_state.md`

## Preconditions

- The scheduled launchd wrapper and its current Codex child are the expected
  run; no unrelated process is editing this repository.
- Local, GitLab, and GitHub heads start at `ec53a327`.
- The inherited documentation-only hosted evidence for `ec53a327` remains
  intentional and will be bundled with this implementation.
- Exact-head CI, Router Image, and the strict deployment-chain audit are green.

## Plan

1. Run pre-change `bin/test-fast`.
2. Add fail-first tests for successful discovery, typed failures, credential-
   free probing, client ownership, and the public CLI/package boundary.
3. Implement the public helper and remove the CLI's duplicate private logic.
4. Run focused client and package-boundary checks plus a real-router smoke.
5. Run `bin/verify`, review, publish the branch, and collect hosted evidence.

## Verification

- focused `connectanum_client` MCP tests
- public package-boundary tests and source/global executable smokes
- `bin/test-fast`
- `bin/verify`
- exact-head hosted workflows after publication

## Decision Log

- 2026-08-16: Selected this slice because endpoint discovery is already proven
  by the published CLI, but consumer applications cannot reuse it without
  copying private probe and challenge-selection behavior.
- 2026-08-16: Keep discovery credential-free and sessionless. Return the
  existing public auth client so grant issuance and lifecycle APIs remain the
  single source of truth.

## Progress

- 2026-08-16: Serena preflight, onboarding, overlap checks, worktree inspection,
  roadmap review, and exact-head health checks pass. Only the preceding
  checkpoint's two post-push evidence files were modified at startup.
- 2026-08-16: Pre-change `bin/test-fast` passes, including the source/global
  router-hosted MCP smokes and isolated router consumer package.
- 2026-08-16: Fail-first coverage reproduced the missing public helper. The
  implementation now performs a credential-free sessionless ping, requires
  HTTP 401, selects an exact realm plus safe `auth_path`, returns the existing
  HTTP-auth client with explicit transport ownership, and emits typed protocol
  failures. Its fresh probe transport cannot inherit credential state from a
  caller-supplied auth transport. The published CLI now delegates to the public
  helper.
- 2026-08-16: Eight focused discovery cases, the complete 304-case client MCP
  suite, all 117 MCP package tests, the public IO discovery boundary, and
  affected-package analysis pass.
- 2026-08-16: The public consumer-boundary structural suite passes and now
  requires the public discovery call while forbidding the removed private
  selector. Source, globally activated package, SCRAM, pub/sub-only, ticket,
  WAMP-CRA, bearer, and JSON-response real-router smokes all pass.
- 2026-08-16: Canonical `bin/verify` passes with zero formatting changes, 117
  Rust core/serializer tests, all 52 FFI tests plus the metrics test mode, 366
  Dart core tests, 117 MCP package tests, the 304-case client/MCP suite, all 97
  benchmark tests and 37 live WAMP workloads, the 454-case router suite, six
  remote-auth tests, 13 native follow-ups, every maintained isolated consumer
  smoke, Chrome, and Dart2Wasm.
- 2026-08-16: A clean strict release-ready dry run validates all seven
  synchronized `3.0.0-beta` Dart package archives, the public executable map,
  and dependency-ordered release plan with zero warnings.

## Handoff

- Active. Review and publication remain; all local verification passes.

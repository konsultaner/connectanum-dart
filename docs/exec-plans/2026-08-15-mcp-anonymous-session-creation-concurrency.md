# Exec Plan: MCP Anonymous Session Creation Concurrency

Status: active
Owner: Codex
Created: 2026-08-15
Last updated: 2026-08-16

## Goal

Make first use of a router-hosted anonymous MCP route create exactly one shared
internal WAMP session when multiple sessionless HTTP requests arrive
concurrently. Concurrent consumers must not leak duplicate internal sessions or
observe different WAMP identities for the same route scope.

## Scope

- In scope:
  - coordinate internal-session creation per retained cache key;
  - cover realm-indexed internal-session creation with the same first-use
    guarantee;
  - prove the anonymous modern sessionless MCP boundary through simultaneous
    direct JSON tool-catalog requests and router session metrics;
  - preserve concurrency between unrelated route scopes and retry after failed
    session creation;
  - keep isolated consumer dependency resolution and global activation bounded
    and retryable when the public package service leaves a connection stale.
- Out of scope:
  - changing anonymous route-scope key construction;
  - changing authenticated external-provider validation or replacement order;
  - changing MCP protocol negotiation or response transport behavior.

## Files Expected To Change

- `packages/connectanum_router/lib/src/router/router_instance/router_binding.dart`
- `packages/connectanum_router/test/router_runtime_test.dart`
- `bin/bootstrap`
- `bin/common.sh`
- `tool/test_verification_scripts.py`
- `ROADMAP.md`
- `docs/project_state.md`
- this execution plan

## Preconditions

- No unrelated Codex process is editing this repository.
- Both maintained `master` branches point at commit `dfb9bac9`, whose exact-head
  deployment chain and strict audit are green.
- Pre-change `bin/test-fast` exits zero across the maintained repository,
  real-router, executable, and isolated consumer-smoke matrix.

## Plan

1. Add a fail-first runtime regression that launches simultaneous first
   requests against one public modern sessionless MCP route and checks the
   active WAMP-session delta.
2. Share one in-flight internal-session creation future per cache key or realm,
   remove completed or failed futures deterministically, and keep unrelated
   scopes independent.
3. Bound and retry every workspace or isolated-consumer Dart pub operation so
   external package-service stalls produce deterministic verification evidence.
4. Run focused tests and `bin/verify`, update durable readiness state, publish
   the implementation to both maintained remotes, and inspect the exact-head
   GitHub deployment chain.

## Verification

- `bin/test-fast`
- Focused fail-first and passing router runtime regression
- `dart analyze packages/connectanum_router`
- Complete router runtime and HTTP-auth provider test matrix
- `bin/verify`
- Exact-head GitHub CI, package dry run, WAMP benchmark, Router Image dry run,
  and strict deployment-chain audit after publication

## Decision Log

- 2026-08-15: The fail-first regression launches 12 simultaneous sessionless
  `tools/list` requests against one anonymous route. The pre-change binding
  reports 12 new active WAMP sessions instead of one because every handler
  passes the completed-session cache check before isolate creation finishes.
- 2026-08-15: Coordinate creation with binding-owned future maps keyed by the
  same cache key or realm used by the completed-session indexes. The first
  request installs its future before yielding; peers await that future;
  completion and failure both remove it with identity-checked cleanup.
- 2026-08-15: The focused regression passes after the change, with all 12 HTTP
  responses successful and exactly one new active WAMP session.
- 2026-08-15: Router analysis is clean, the complete 96-case router runtime
  suite passes with the new concurrency regression, and all 10 HTTP-auth
  provider tests pass.
- 2026-08-15: Four post-change `bin/verify` attempts reached only external
  clean-cache package resolution before being stopped after their individual
  Dart pub sockets remained idle for more than 30 minutes. Three runs reached
  the server-only MCP consumer; the furthest run passed that consumer and the
  client-only MCP consumer before its isolated global activation stalled. All
  preceding formatting, Rust/FFI, audit, core, MCP, and compatibility stages
  were green. Independent pub.dev archive probes reproduced DNS and connection
  timeouts, connection resets, and partial-transfer timeouts; fresh archive
  transfers could recover while the Dart socket stayed stale, so this is an
  external network blocker rather than a test failure.
- 2026-08-16: Add one shared Dart pub wrapper that gives each workspace,
  isolated consumer, and path-package global-activation operation three
  180-second attempts with five-second delays by default. A fail-first shell
  regression initially failed because the helper did not exist; the complete
  16-case verification-script suite passes after implementation.
- 2026-08-16: The first guarded `bin/test-fast` attempt terminated three stale
  clean-cache MCP server-consumer resolutions and exited with status 124
  instead of hanging indefinitely. After the external service recovered, a
  canonical rerun exited zero across analysis, all package suites, every
  isolated and globally activated consumer smoke, all 37 live WAMP workloads,
  and the router CLI MCP consumer.
- 2026-08-16: Canonical `bin/verify` exits zero with formatting unchanged; 117
  Rust core checks; 52 FFI tests plus the metrics feature check; 366 core Dart
  tests; 116 MCP tests; the complete 293-case MCP/client suite; all 97
  benchmark tests including 37 live WAMP workloads; all 446 router cases; six
  remote-auth tests; 13 native follow-ups; every maintained consumer and
  global-activation smoke; Chrome; and Dart2Wasm green. No Dart pub retry was
  required on the passing run.

## Handoff

- Implementation and complete local verification are green. Publication to
  both maintained remotes and exact-head hosted evidence remain pending.

# Exec Plan: Router-Hosted MCP Example Subscription Meta Smoke

Status: complete; hosted CI evidence clean
Owner: Codex
Created: 2026-05-09
Last updated: 2026-05-09

## Goal

Make the runnable router-hosted MCP example prove that consumer applications
can use WAMP subscription metadata over both lifecycle-free direct JSON-RPC
batches and initialized Streamable HTTP `tools/call` batches while a pub/sub
subscription is active.

## Context

- Current priority is router-hosted MCP and downstream application development
  readiness.
- Generated consumer smoke already covers WAMP subscription metadata batches;
  the public example still needed matching proof.
- The local Dart SDK hook runner only forwards cache-safe
  `hooks.user_defines`; exported `CONNECTANUM_*` variables are not a reliable
  way for root scripts to suppress hook-side native builds during package test
  runs.

## Scope

- Add workspace-level hook user defines in the root pubspec so canonical root
  scripts explicitly skip client/router hook-side native builds while the root
  scripts provide or build the runtime library.
- Extend `packages/connectanum_router/example/router_hosted_mcp.dart` with
  direct JSON and Streamable HTTP WAMP subscription metadata batch helpers.
- Keep direct JSON batches lifecycle-free by omitting Streamable session
  headers and asserting no session id or SSE cursor changes.
- Keep Streamable batches on the initialized MCP session and assert the SSE
  cursor advances after each metadata batch.

## Verification

- Focused native WAMP transport integration repro passed after the workspace
  hook user defines were added:
  `cd packages/connectanum_bench && env -u CONNECTANUM_NATIVE_LIB CONNECTANUM_SKIP_NATIVE_BUILD=1 dart test test/wamp_transport_integration_test.dart --chain-stack-traces -r expanded`
  (03:16).
- Pre-example-edit `bin/test-fast` passed on 2026-05-09 with isolated `TMPDIR`.
- Focused router-hosted MCP example smoke passed on 2026-05-09 with isolated
  `TMPDIR`:
  `bash -lc 'source bin/common.sh; cd_repo_root; run_router_hosted_mcp_example_smoke'`.
- Full local `bin/verify` passed on 2026-05-09 with isolated `TMPDIR`.
- `git diff --check` passed on 2026-05-09.
- Commit `2b9d060` (`test: cover mcp example subscription meta`) was pushed
  to `origin/add-router` and `github/add-router` on 2026-05-09.
- Hosted GitHub `CI` run `25589519273` for `2b9d060` completed successfully on
  2026-05-09 with `Fast Checks` (4m22s) and `Full Verify` (5m51s) green.
- Hosted `WAMP Profile Benchmarks` run `25589519288` completed successfully on
  2026-05-09 with `Linux WAMP profile gates` green (8m20s).
- Hosted `Dart Package Publish Dry Run` run `25589519295` completed
  successfully on 2026-05-09 with `Publish Dry Run` green and covering the
  checked-out head.
- Deployment-chain audit passed on 2026-05-09 with clean latest CI and clean
  relevant Dart package publish dry-run evidence.
- Strict deployment audit still reports operator-side release gaps: branch
  protection and required status checks are absent,
  `.github/workflows/router-image.yml` is not discoverable from the default
  branch, and `ghcr.io/konsultaner/connectanum-router` is not visible.

## Decision Log

- Keep the root hook user defines in the workspace pubspec instead of published
  package pubspecs, preserving consumer default hook behavior while making
  repository verification deterministic.
- Mirror the generated consumer subscription metadata shape: direct JSON uses
  raw `wamp.subscription.*` methods with kwargs, and Streamable HTTP uses
  `tools/call` with nested positional WAMP arguments.

## Handoff

Implementation, local verification, hosted CI, WAMP profile, and standard
deployment-chain audit evidence are clean for `2b9d060`. Remaining strict audit
failures are operator-side release controls: branch protection/required checks,
default-branch router workflow visibility, and GHCR router package visibility.

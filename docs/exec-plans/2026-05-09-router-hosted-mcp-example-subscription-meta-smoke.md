# Exec Plan: Router-Hosted MCP Example Subscription Meta Smoke

Status: complete; local verification clean; commit and hosted evidence pending
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
- Commit, push, and hosted evidence are pending.

## Decision Log

- Keep the root hook user defines in the workspace pubspec instead of published
  package pubspecs, preserving consumer default hook behavior while making
  repository verification deterministic.
- Mirror the generated consumer subscription metadata shape: direct JSON uses
  raw `wamp.subscription.*` methods with kwargs, and Streamable HTTP uses
  `tools/call` with nested positional WAMP arguments.

## Handoff

Implementation, focused example smoke, fast verification, diff check, and full
local verification are clean. Commit, push, and hosted evidence remain.

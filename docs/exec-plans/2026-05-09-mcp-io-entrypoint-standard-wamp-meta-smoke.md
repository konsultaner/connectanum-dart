# Exec Plan: MCP IO Entrypoint Standard WAMP Meta Smoke

Status: complete; local verification clean; hosted evidence pending
Owner: Codex
Created: 2026-05-09
Last updated: 2026-05-09

## Goal

Prove that a consumer application depending on `connectanum_mcp` can import
only `package:connectanum_mcp/connectanum_mcp_io.dart` and use standard WAMP
session and subscription meta helpers over lifecycle-free direct JSON requests.

## Context

- Current priority is router-hosted MCP and downstream application development
  readiness.
- Lower-level client tests already cover the broader WAMP meta helper set, but
  the IO package-boundary smoke only proved direct registration matching.
- The previous IO entrypoint slices covered direct WAMP API listing, direct
  Connectanum tool/meta calls, auth/session helpers, Streamable
  resources/prompts, and Streamable pub/sub helpers.

## Scope

- Extend `packages/connectanum_mcp/test/io_client_export_test.dart`.
- Add public-import coverage for session meta helpers:
  `countWampSessions`, `listWampSessions`, and `getWampSession`.
- Add public-import coverage for subscription meta helpers:
  `matchWampSubscription`, `getWampSubscription`, and
  `countWampSubscriptionSubscribers`.
- Assert that all requests stay lifecycle-free direct JSON `connectanum.tool.call`
  POSTs without `MCP-Session-Id`.

## Verification

- Pre-change `bin/test-fast` passed on 2026-05-09 with isolated `TMPDIR`.
- Focused `dart test packages/connectanum_mcp/test/io_client_export_test.dart`
  passed on 2026-05-09 with isolated `TMPDIR`.
- Post-change `bin/test-fast` passed on 2026-05-09 with isolated `TMPDIR`.
- Full local `bin/verify` passed on 2026-05-09 with isolated `TMPDIR`.

## Decision Log

- 2026-05-09: Chose this slice because standard WAMP session/subscription meta
  helpers are important for downstream agent/app diagnostics, and public IO
  entrypoint evidence still lacked that package-boundary proof.

## Handoff

Implementation and full local verification are complete. Commit/push and hosted
CI/deployment-chain evidence remain.

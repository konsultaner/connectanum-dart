# Exec Plan: MCP IO Entrypoint Direct Tool Meta Smoke

Status: complete; local verification clean; hosted evidence pending
Owner: Codex
Created: 2026-05-09
Last updated: 2026-05-09

## Goal

Prove that a consumer application depending on `connectanum_mcp` can import
only `package:connectanum_mcp/connectanum_mcp_io.dart` and use direct JSON
Connectanum tool/meta helpers without creating or mutating a Streamable HTTP MCP
session.

## Context

- Current priority is router-hosted MCP and downstream application development
  readiness.
- Lower-level client tests already cover direct JSON tool and meta helper
  request shapes, but the IO package-boundary smoke only proved
  `listWampApi(..., directJson: true)`.
- The previous IO entrypoint slices covered direct WAMP API listing,
  auth/session helpers, Streamable resource/prompt helpers, and Streamable
  pub/sub helpers.

## Scope

- Extend `packages/connectanum_mcp/test/io_client_export_test.dart`.
- Add public-import coverage for `listConnectanumToolsDirect`,
  `callConnectanumToolDirect`, and `callConnectanumMethodDirect`.
- Cover a raw WAMP meta procedure method call and the higher-level direct
  WAMP meta helper path through `matchWampRegistration(..., directJson: true)`.
- Assert that all requests stay lifecycle-free JSON POSTs without
  `MCP-Session-Id`.

## Verification

- Pre-change `bin/test-fast` passed on 2026-05-09 with isolated `TMPDIR`.
- Focused `dart test packages/connectanum_mcp/test/io_client_export_test.dart`
  passed on 2026-05-09 with isolated `TMPDIR`.
- Post-change `bin/test-fast` passed on 2026-05-09 with isolated `TMPDIR`.
- Full local `bin/verify` passed on 2026-05-09 with isolated `TMPDIR`.

## Decision Log

- 2026-05-09: Chose this slice because direct JSON tool/meta API access is a
  current downstream-readiness priority, and the public IO entrypoint still
  lacked package-boundary evidence for the direct Connectanum helper methods.

## Handoff

Implementation and full local verification are complete. Commit/push and hosted
CI/deployment-chain evidence remain.

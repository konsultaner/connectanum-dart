# Exec Plan: MCP Direct Batch Header Smoke

Status: complete; local verification clean, hosted evidence pending
Owner: Codex
Created: 2026-05-10
Last updated: 2026-05-10

## Goal

Make direct JSON-RPC batch calls as usable as single direct JSON-RPC calls for
consumer applications by allowing per-call HTTP headers without leaking
Streamable HTTP session state.

## Scope

- In scope: public `McpStreamableHttpClient.postBatch` custom headers, package
  coverage for direct JSON-RPC batches with active Streamable sessions,
  generated client-only package smoke coverage, and router-hosted consumer smoke
  coverage through public package APIs.
- Out of scope: new MCP batch semantics, router authorization policy changes, or
  release workflow changes.

## Files Expected To Change

- `packages/connectanum_client/lib/src/mcp/streamable_http_client.dart`
- `packages/connectanum_client/test/mcp/streamable_http_client_test.dart`
- `bin/common.sh`
- `docs/project_state.md`
- `docs/exec-plans/2026-05-10-mcp-direct-batch-header-smoke.md`

## Preconditions

- Pre-change `bin/test-fast` passed on 2026-05-10 with isolated `TMPDIR`.
- Existing docs-only hosted-evidence updates for the previous direct
  notification plan are uncommitted and will be bundled with this
  implementation.

## Plan

1. Add a `headers` argument to `McpStreamableHttpClient.postBatch` and forward it
   through the same request-header path used by `post`, `request`, and
   `notification`.
2. Extend package tests so a direct JSON-RPC batch can pass a neutral consumer
   header while omitting `MCP-Session-Id` and preserving active Streamable
   session state.
3. Extend generated neutral package smokes so client-only and router-hosted
   consumer paths compile and run with the public batch header API.
4. Run focused tests, full local verification, commit, push, and collect hosted
   deployment-chain evidence.

## Verification

- Pre-change `bin/test-fast` passed on 2026-05-10 with isolated `TMPDIR`.
- `dart format
  packages/connectanum_client/lib/src/mcp/streamable_http_client.dart
  packages/connectanum_client/test/mcp/streamable_http_client_test.dart`
  passed on 2026-05-10.
- `bash -n bin/common.sh` passed on 2026-05-10.
- Focused `dart test
  packages/connectanum_client/test/mcp/streamable_http_client_test.dart`
  passed on 2026-05-10.
- Focused `run_mcp_client_package_smoke` passed on 2026-05-10.
- Focused `run_mcp_consumer_package_smoke` passed on 2026-05-10.
- Post-change `bin/test-fast` passed on 2026-05-10 with isolated `TMPDIR`.
- Full local `bin/verify` passed on 2026-05-10 with isolated `TMPDIR`.
- Hosted deployment-chain evidence is pending until the implementation commit is
  pushed.

## Decision Log

- 2026-05-10: Chose to extend `postBatch` with the existing header-forwarding
  contract instead of adding a separate direct-batch API, keeping the direct
  JSON-RPC surface consistent for consumer applications.

## Handoff

Implementation and full local verification are complete. Push and hosted
deployment-chain evidence still need to be collected for the implementation
commit.

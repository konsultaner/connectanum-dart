# Exec Plan: MCP Batch Topic Meta Smoke

Status: complete; local verification clean
Owner: Codex
Created: 2026-05-09
Last updated: 2026-05-09

## Goal

Make router-hosted MCP batch paths prove that a consumer application can
discover and describe configured WAMP topic metadata, including event schema
and publish/subscribe capabilities, without relying on single-request helpers.

## Context

- Current priority is router-hosted MCP and downstream application development
  readiness.
- Direct JSON and initialized Streamable HTTP single-request topic metadata
  smokes are complete for both the runnable public example and generated
  consumer package smoke.
- Existing batch WAMP metadata smokes cover sessions and registrations, but
  they do not yet cover configured topic metadata in the same batched request
  shapes used by agents and applications.

## Scope

- Extend the generated consumer package direct JSON batch WAMP metadata smoke
  to include `connectanum.api.list` and `connectanum.api.describe` topic
  metadata calls.
- Extend the generated consumer package initialized Streamable HTTP batch WAMP
  metadata smoke to include equivalent `tools/call` topic metadata calls.
- Mirror the same batch topic metadata assertions in the runnable
  router-hosted MCP public example.
- Preserve existing lifecycle guarantees: direct JSON batches must stay
  session-free, and Streamable batches must advance the existing SSE/session
  cursor without changing the session id.

## Verification

- Pre-change `bin/test-fast` passed on 2026-05-09 with isolated `TMPDIR`.
- Focused router-hosted MCP example plus generated consumer package smoke
  passed on 2026-05-09 with isolated `TMPDIR` via
  `bash -lc 'source bin/common.sh; cd_repo_root; run_router_hosted_mcp_example_smoke; run_mcp_consumer_package_smoke'`.
- Post-change `bin/test-fast` passed on 2026-05-09 with isolated `TMPDIR`.
- Full local `bin/verify` passed on 2026-05-09 with isolated `TMPDIR`.

## Decision Log

- Keep this as smoke coverage in both generated consumer and public example
  paths so batch-mode MCP metadata stays proven for package consumers and
  human-runnable examples.

## Handoff

Implementation and local verification are complete. Commit, push, and hosted
deployment-chain evidence are pending.

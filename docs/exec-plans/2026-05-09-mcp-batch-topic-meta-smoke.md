# Exec Plan: MCP Batch Topic Meta Smoke

Status: complete; hosted CI evidence clean
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
- Commit `cb88045` (`test: cover mcp batch topic metadata`) was pushed to
  `origin/add-router` and `github/add-router` on 2026-05-09.
- Hosted GitHub `CI` run `25595463999` for `cb88045` completed successfully on
  2026-05-09 with `Fast Checks` (4m14s) and `Full Verify` (5m59s) green.
- Hosted GitHub `WAMP Profile Benchmarks` run `25595464000` for `cb88045`
  completed successfully on 2026-05-09 with `Linux WAMP profile gates`
  (7m44s) green.
- Hosted GitHub `Dart Package Publish Dry Run` run `25595464002` for
  `cb88045` completed successfully on 2026-05-09 with `Publish Dry Run` green.
- Deployment-chain audit passed on 2026-05-09 with clean latest CI and clean
  relevant Dart package publish dry-run evidence. Strict deployment audit still
  reports operator-side release gaps: branch protection and required status
  checks are absent, `.github/workflows/router-image.yml` is not discoverable
  from the default branch, and `ghcr.io/konsultaner/connectanum-router` is not
  visible.

## Decision Log

- Keep this as smoke coverage in both generated consumer and public example
  paths so batch-mode MCP metadata stays proven for package consumers and
  human-runnable examples.

## Handoff

Implementation, local verification, push, and hosted deployment-chain evidence
are complete. Remaining strict-audit findings are release-ops gates outside
this implementation slice.

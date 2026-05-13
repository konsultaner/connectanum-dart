# Exec Plan: MCP Pub/Sub Queue Overflow Smoke

Status: complete; hosted CI evidence clean
Owner: Codex
Created: 2026-05-09
Last updated: 2026-05-09

## Goal

Make router-hosted MCP pub/sub smoke coverage prove that consumer applications
can rely on bounded subscription queues: when a consumer falls behind, the MCP
subscription drops the oldest buffered events, retains the newest event, and
reports dropped and remaining counts through the public client helper surface.

## Context

- Current priority is router-hosted MCP and downstream application development
  readiness.
- Existing smokes prove direct JSON and initialized Streamable HTTP subscribe,
  publish, poll, and unsubscribe flows, including batch-mode pub/sub.
- The missing consumer-facing proof is queue overflow behavior for bounded
  MCP-created WAMP subscriptions. That matters for applications and agents
  using small queues to cap memory under bursty topic traffic.

## Scope

- Extend the generated consumer package smoke to subscribe with `queueLimit: 1`,
  publish multiple service events, poll the MCP subscription, and assert that
  only the newest event is retained with a non-zero dropped count.
- Cover both lifecycle-free direct JSON and initialized Streamable HTTP paths.
- Mirror the same queue overflow assertions in the runnable public
  router-hosted MCP example.
- Preserve existing lifecycle guarantees: direct JSON overflow checks must not
  create or mutate Streamable session state, and Streamable checks must retain
  the active session while advancing SSE state.

## Verification

- Pre-change `bin/test-fast` passed on 2026-05-09 with isolated `TMPDIR`.
- Focused router-hosted MCP example plus generated consumer package smoke
  passed on 2026-05-09 with isolated `TMPDIR` via
  `bash -lc 'source bin/common.sh; cd_repo_root; run_router_hosted_mcp_example_smoke; run_mcp_consumer_package_smoke'`.
- Post-change `bin/test-fast` passed on 2026-05-09 with isolated `TMPDIR`.
- Full local `bin/verify` passed on 2026-05-09 with isolated `TMPDIR`.
- Commit `d1679a9` (`test: cover mcp pubsub queue overflow`) was pushed to
  `origin/add-router` and `github/add-router` on 2026-05-09.
- Hosted GitHub `CI` run `25596433388` for `d1679a9` completed successfully on
  2026-05-09 with `Fast Checks` (4m20s) and `Full Verify` (5m35s) green.
- Hosted GitHub `WAMP Profile Benchmarks` run `25596433375` for `d1679a9`
  completed successfully on 2026-05-09 with `Linux WAMP profile gates` (8m02s)
  green.
- Hosted GitHub `Dart Package Publish Dry Run` run `25596433396` for
  `d1679a9` completed successfully on 2026-05-09 with `Publish Dry Run` green.
- Deployment-chain audit passed on 2026-05-09 with clean latest CI and clean
  relevant Dart package publish dry-run evidence.
- Strict deployment audit still reports operator-side release gaps: branch
  protection and required status checks are absent,
  `.github/workflows/router-image.yml` is not discoverable from the default
  branch, and `ghcr.io/konsultaner/connectanum-router` is not visible.

## Decision Log

- Keep this as smoke coverage in both generated consumer and public example
  paths because queue overflow behavior is a consumer application contract, not
  only an internal unit-test detail.

## Handoff

Implementation, local verification, push, and hosted deployment-chain evidence
are complete. Remaining strict-audit findings are operator-side release gaps
outside this MCP queue-overflow smoke slice.

# Exec Plan: MCP Consumer Generic JSON-RPC Smoke

Status: complete locally; hosted CI evidence pending
Owner: Codex
Created: 2026-05-07
Last updated: 2026-05-07

## Goal

Prove from the generated neutral consumer package that downstream agents can
use the public generic JSON-RPC client surface against router-hosted MCP direct
JSON endpoints without relying on typed helper wrappers or private project
assumptions.

## Scope

- In scope:
  - Extend `run_mcp_consumer_package_smoke` in `bin/common.sh`.
  - Use public `McpStreamableHttpClient.request(...)` and `post(...)` calls.
  - Prove `connectanum.tools.list`, `connectanum.tool.call`, and
    `connectanum.api.describe` work over lifecycle-free direct JSON.
  - Run the generic direct JSON assertions before Streamable initialization
    and again while a Streamable session is active.
  - Assert the generic direct JSON path does not mutate Streamable session or
    SSE cursor state.
  - Bundle existing hosted-evidence docs updates from the previous MCP entity
    meta smoke checkpoint.
- Out of scope:
  - Router protocol behavior changes.
  - New public API methods.
  - Private downstream application references.
  - Documentation-only cleanup.

## Files Expected To Change

- `bin/common.sh`
- `docs/project_state.md`
- `docs/exec-plans/2026-05-07-mcp-consumer-generic-jsonrpc-smoke.md`
- Existing docs-only hosted-evidence updates for the previous MCP entity meta
  smoke plan.

## Preconditions

- Latest pushed implementation commit `586801e` has clean hosted CI evidence.
- The default system temp native runtime lock is currently held by an existing
  long-lived router process outside this task, so local validation that starts
  a native runtime uses an isolated `TMPDIR` instead of stopping that process.
- Pre-change `bin/test-fast` with default `TMPDIR` reached the generated MCP
  consumer smoke successfully but failed later on the external native runtime
  lock.
- Pre-change `bin/test-fast` with isolated `TMPDIR` passed on 2026-05-07.

## Plan

1. Add a generic direct JSON-RPC smoke helper to the generated neutral
   consumer package.
2. Call it in the lifecycle-free direct JSON flow and in the direct JSON
   after Streamable initialization flow.
3. Run focused syntax/smoke checks, post-change `bin/test-fast`, and
   `bin/verify` with isolated `TMPDIR`.
4. Commit implementation plus bundled state updates, push both remotes, and
   inspect hosted GitHub evidence.

## Verification

- Default-temp pre-change `bin/test-fast` reached the generated MCP consumer
  package smoke successfully, then failed later because an existing long-lived
  router process outside this task held the native runtime lock.
- Pre-change `bin/test-fast` passed on 2026-05-07 with isolated `TMPDIR`.
- Focused checks passed on 2026-05-07:
  `bash -n bin/common.sh bin/test-fast bin/test-all`, `git diff --check`, and
  `bash -lc 'source bin/common.sh; cd_repo_root; run_mcp_consumer_package_smoke'`
  with isolated `TMPDIR`.
- Post-change `bin/test-fast` passed on 2026-05-07 with isolated `TMPDIR`.
- Full local `bin/verify` passed on 2026-05-07 with isolated `TMPDIR`.

## Decision Log

- 2026-05-07: Chose this slice because typed MCP helper coverage is now broad,
  but downstream agents may use the generic JSON-RPC client surface directly.
  This keeps the package-readiness smoke focused on public APIs and neutral
  consumer behavior.

## Handoff

Implementation and local verification are complete. Commit, push, hosted CI,
and deployment-chain audit evidence are pending.

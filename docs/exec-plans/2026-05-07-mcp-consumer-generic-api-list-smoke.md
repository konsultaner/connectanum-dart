# Exec Plan: MCP Consumer Generic API List Smoke

Status: complete locally; hosted CI evidence pending
Owner: Codex
Created: 2026-05-07
Last updated: 2026-05-07

## Goal

Prove from the generated neutral consumer package that downstream agents can
call the router-hosted MCP `connectanum.api.list` method through public generic
JSON-RPC access, without typed helper wrappers or private project assumptions.

## Scope

- In scope:
  - Extend `run_mcp_consumer_package_smoke` in `bin/common.sh`.
  - Use public `McpStreamableHttpClient.request(...)`.
  - Prove direct JSON-RPC method `connectanum.api.list` returns the configured
    procedure and topic catalog.
  - Run the generic API-list assertion before Streamable initialization and
    again while a Streamable session is active through the existing generic
    direct JSON-RPC smoke path.
  - Assert the generic direct JSON catalog request does not mutate Streamable
    session id or SSE cursor state.
  - Bundle existing hosted-evidence docs updates from the previous MCP generic
    pub/sub smoke checkpoint.
- Out of scope:
  - Router protocol behavior changes.
  - New public API methods.
  - Private downstream application references.
  - Documentation-only cleanup.

## Files Expected To Change

- `bin/common.sh`
- `docs/project_state.md`
- `docs/exec-plans/2026-05-07-mcp-consumer-generic-api-list-smoke.md`
- Existing docs-only hosted-evidence updates for the previous MCP generic
  pub/sub smoke plan.

## Preconditions

- Latest pushed implementation commit `7fa39d1` has clean hosted CI evidence.
- The default system temp native runtime lock was previously held by an
  existing long-lived router process outside this task, so local validation
  that starts a native runtime uses an isolated `TMPDIR`.
- Pre-change `bin/test-fast` passed on 2026-05-07 with isolated `TMPDIR`.

## Plan

1. Add a standalone generic direct JSON-RPC `connectanum.api.list` assertion to
   the generated neutral consumer smoke.
2. Reuse the existing generic direct JSON-RPC smoke before Streamable
   initialization and after Streamable initialization.
3. Run focused syntax/smoke checks, post-change `bin/test-fast`, and
   `bin/verify` with isolated `TMPDIR`.
4. Commit implementation plus bundled state updates, push both remotes, and
   inspect hosted GitHub evidence.

## Verification

- Pre-change `bin/test-fast` passed on 2026-05-07 with isolated `TMPDIR`.
- Focused checks passed on 2026-05-07:
  `bash -n bin/common.sh bin/test-fast bin/test-all`, `git diff --check`,
  and
  `bash -lc 'source bin/common.sh; cd_repo_root; run_mcp_consumer_package_smoke'`
  with isolated `TMPDIR`.
- Post-change `bin/test-fast` passed on 2026-05-07 with isolated `TMPDIR`.
- Full local `bin/verify` passed on 2026-05-07 with isolated `TMPDIR`.

## Decision Log

- 2026-05-07: Chose this slice because the generated neutral consumer smoke
  already proves generic `connectanum.tools.list`, `connectanum.tool.call`,
  `connectanum.api.describe`, and pub/sub direct JSON-RPC methods, while
  standalone generic `connectanum.api.list` still lacked consumer-package
  coverage.

## Handoff

Implementation and local verification are complete. Commit, push, hosted CI,
and deployment-chain audit evidence are pending.

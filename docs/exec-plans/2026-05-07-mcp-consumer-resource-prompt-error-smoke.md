# Exec Plan: MCP Consumer Resource And Prompt Error Smoke

Status: complete; local verification clean; hosted evidence pending
Owner: Codex
Created: 2026-05-07
Last updated: 2026-05-07

## Goal

Prove from the generated neutral consumer package that downstream agents can
use public generic direct JSON-RPC calls for standard router-hosted MCP
resource and prompt error paths, without typed helper wrappers or private
project assumptions.

## Scope

- In scope:
  - Extend `run_mcp_consumer_package_smoke` in `bin/common.sh`.
  - Use public `McpStreamableHttpClient.request(...)` and `post(...)`.
  - Prove generic direct JSON-RPC error responses for missing
    `resources/read` and `prompts/get` targets.
  - Run the assertions before Streamable initialization and again while a
    Streamable session is active.
  - Assert direct JSON-RPC resource/prompt errors and recovery calls do not
    mutate Streamable session id or SSE cursor state.
  - Bundle existing hosted-evidence docs updates from the previous MCP generic
    resources/prompts smoke checkpoint.
- Out of scope:
  - Router protocol behavior changes.
  - New public API methods.
  - Private downstream application references.
  - Documentation-only cleanup.

## Files Expected To Change

- `bin/common.sh`
- `docs/project_state.md`
- `docs/exec-plans/2026-05-07-mcp-consumer-resource-prompt-error-smoke.md`
- Existing docs-only hosted-evidence updates for the previous MCP generic
  resources/prompts smoke plan.

## Preconditions

- Latest pushed implementation commit `e4deead` has clean hosted CI evidence.
- The default system temp native runtime lock was previously held by an
  existing long-lived router process outside this task, so local validation
  that starts a native runtime uses an isolated `TMPDIR`.
- Pre-change `bin/test-fast` passed on 2026-05-07 with isolated `TMPDIR`.

## Plan

1. Add a generic direct JSON-RPC resource/prompt error helper to the generated
   neutral consumer package.
2. Call it in the lifecycle-free direct JSON flow and in the direct JSON after
   Streamable initialization flow.
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

- 2026-05-07: Chose this slice because successful generic direct JSON-RPC
  resource/prompt access is covered, while generic public error handling for
  missing standard MCP resources and prompts still lacked generated
  consumer-package coverage.

## Handoff

Complete locally. Hosted evidence is pending after the implementation commit is
pushed.

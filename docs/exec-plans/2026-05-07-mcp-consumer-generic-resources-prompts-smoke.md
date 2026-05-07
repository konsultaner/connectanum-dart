# Exec Plan: MCP Consumer Generic Resources And Prompts Smoke

Status: complete locally; hosted CI evidence pending
Owner: Codex
Created: 2026-05-07
Last updated: 2026-05-07

## Goal

Prove from the generated neutral consumer package that downstream agents can
use public generic JSON-RPC calls for standard router-hosted MCP resources and
prompts, without typed helper wrappers or private project assumptions.

## Scope

- In scope:
  - Extend `run_mcp_consumer_package_smoke` in `bin/common.sh`.
  - Use public `McpStreamableHttpClient.request(...)` and `post(...)`.
  - Prove direct JSON-RPC methods `resources/list`, `resources/read`,
    `resources/templates/list`, `prompts/list`, and `prompts/get`.
  - Run the generic resources/prompts assertions before Streamable
    initialization and again while a Streamable session is active through the
    existing direct JSON smoke path.
  - Assert the generic direct JSON resource/prompt requests do not mutate
    Streamable session id or SSE cursor state.
  - Bundle existing hosted-evidence docs updates from the previous MCP generic
    API list smoke checkpoint.
- Out of scope:
  - Router protocol behavior changes.
  - New public API methods.
  - Private downstream application references.
  - Documentation-only cleanup.

## Files Expected To Change

- `bin/common.sh`
- `docs/project_state.md`
- `docs/exec-plans/2026-05-07-mcp-consumer-generic-resources-prompts-smoke.md`
- Existing docs-only hosted-evidence updates for the previous MCP generic API
  list smoke plan.

## Preconditions

- Latest pushed implementation commit `6bd5d8e` has clean hosted CI evidence.
- The default system temp native runtime lock was previously held by an
  existing long-lived router process outside this task, so local validation
  that starts a native runtime uses an isolated `TMPDIR`.
- Pre-change `bin/test-fast` passed on 2026-05-07 with isolated `TMPDIR`.

## Plan

1. Add a generic direct JSON-RPC resources/prompts helper to the generated
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

- 2026-05-07: Chose this slice because typed resource/prompt helpers and batch
  paths are already covered, while generic public JSON-RPC access to standard
  MCP resource and prompt methods still lacked generated consumer-package
  coverage.

## Handoff

Implementation and local verification are complete. Commit, push, hosted CI,
and deployment-chain audit evidence are pending.
